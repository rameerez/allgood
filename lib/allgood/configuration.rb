module Allgood
  class Configuration
    attr_reader :checks
    attr_accessor :default_timeout

    def initialize
      @checks = []
      @default_timeout = 10 # Default timeout of 10 seconds
    end

    def check(name, **options, &block)
      check_info = {
        name: name,
        block: block,
        timeout: options[:timeout] || @default_timeout,
        options: options,
        status: :pending
      }

      # Handle rate limiting
      if options[:run]
        begin
          check_info[:rate] = parse_run_frequency(options[:run])
        rescue ArgumentError => e
          check_info[:status] = :skipped
          check_info[:skip_reason] = "Invalid run frequency: #{e.message}"
          @checks << check_info
          return
        end
      end

      # Handle environment-specific options
      if options[:only]
        environments = Array(options[:only])
        unless environments.include?(Rails.env.to_sym)
          check_info[:status] = :skipped
          check_info[:skip_reason] = "Only runs in #{environments.join(', ')}"
          @checks << check_info
          return
        end
      end

      if options[:except]
        environments = Array(options[:except])
        if environments.include?(Rails.env.to_sym)
          check_info[:status] = :skipped
          check_info[:skip_reason] = "This check doesn't run in #{environments.join(', ')}"
          @checks << check_info
          return
        end
      end

      # Handle conditional checks
      if options[:if]
        condition = options[:if]
        unless condition.is_a?(Proc) ? condition.call : condition
          check_info[:status] = :skipped
          check_info[:skip_reason] = "Check condition not met"
          @checks << check_info
          return
        end
      end

      if options[:unless]
        condition = options[:unless]
        if condition.is_a?(Proc) ? condition.call : condition
          check_info[:status] = :skipped
          check_info[:skip_reason] = "Check `unless` condition met"
          @checks << check_info
          return
        end
      end

      check_info[:status] = :active
      @checks << check_info
    end

    def run_check(&block)
      CheckRunner.new.instance_eval(&block)
    end

    def should_run_check?(check)
      return true unless check[:rate]

      cache_key = "allgood:last_run:#{check[:name].parameterize}"
      runs_key = "allgood:runs_count:#{check[:name].parameterize}:#{current_period(check[:rate])}"
      error_key = "allgood:error:#{check[:name].parameterize}"
      last_result_key = "allgood:last_result:#{check[:name].parameterize}"

      last_run = Allgood::CacheStore.instance.read(cache_key)
      period_runs = Allgood::CacheStore.instance.read(runs_key).to_i
      last_result = Allgood::CacheStore.instance.read(last_result_key)

      current_period_key = current_period(check[:rate])
      stored_period = Allgood::CacheStore.instance.read("allgood:current_period:#{check[:name].parameterize}")

      # If we're in a new period, reset the counter
      if stored_period != current_period_key
        period_runs = 0
        Allgood::CacheStore.instance.write("allgood:current_period:#{check[:name].parameterize}", current_period_key)
        Allgood::CacheStore.instance.write(runs_key, 0)
      end

      # If there's an error, wait until next period
      if previous_error = Allgood::CacheStore.instance.read(error_key)
        next_period = next_period_start(check[:rate])
        rate_info = "Rate limited (#{period_runs}/#{check[:rate][:max_runs]} runs this #{check[:rate][:period]})"
        check[:skip_reason] = "#{rate_info}. Waiting until #{next_period.strftime('%H:%M:%S %Z')} to retry failed check"
        return false
      end

      # If we haven't exceeded the max runs for this period
      if period_runs < check[:rate][:max_runs]
        Allgood::CacheStore.instance.write(cache_key, Time.current)
        Allgood::CacheStore.instance.write(runs_key, period_runs + 1)
        true
      else
        next_period = next_period_start(check[:rate])
        rate_info = "Rate limited (#{period_runs}/#{check[:rate][:max_runs]} runs this #{check[:rate][:period]})"
        next_run = "Next check at #{next_period.strftime('%H:%M:%S %Z')}"
        check[:skip_reason] = "#{rate_info}. #{next_run}"
        false
      end
    end

    private

    def parse_run_frequency(frequency)
      case frequency.to_s.downcase
      when /(\d+)\s+times?\s+per\s+(day|hour)/i
        max_runs, period = $1.to_i, $2
        if max_runs <= 0
          raise ArgumentError, "Number of runs must be positive"
        end
        if max_runs > 1000
          raise ArgumentError, "Maximum 1000 runs per period allowed"
        end
        { max_runs: max_runs, period: period }
      else
        raise ArgumentError, "Unsupported frequency format. Use 'N times per day' or 'N times per hour'"
      end
    end

    def current_period(rate)
      case rate[:period]
      when 'day'
        Time.current.strftime('%Y-%m-%d')
      when 'hour'
        Time.current.strftime('%Y-%m-%d-%H')
      end
    end

    def new_period?(last_run, rate)
      case rate[:period]
      when 'day'
        !last_run.to_date.equal?(Time.current.to_date)
      when 'hour'
        last_run.strftime('%Y-%m-%d-%H') != Time.current.strftime('%Y-%m-%d-%H')
      end
    end

    def next_period_start(rate)
      case rate[:period]
      when 'day'
        Time.current.beginning_of_day + 1.day
      when 'hour'
        Time.current.beginning_of_hour + 1.hour
      else
        raise ArgumentError, "Unsupported period: #{rate[:period]}"
      end
    end
  end

  class CheckRunner
    def make_sure(condition, message = nil)
      if condition
        { success: true, message: message || "Check passed" }
      else
        raise CheckFailedError.new(message || "Check failed")
      end
    end

    def expect(actual)
      Expectation.new(actual)
    end
  end

  class Expectation
    def initialize(actual)
      @actual = actual
    end

    def to_eq(expected)
      if @actual == expected
        { success: true, message: "Got: #{@actual || 'nil'}" }
      else
        raise CheckFailedError.new("Expected #{expected} to equal #{@actual || 'nil'} but it doesn't")
      end
    end

    def to_be_greater_than(expected)
      if @actual > expected
        { success: true, message: "Got: #{@actual || 'nil'} (> #{expected})" }
      else
        raise CheckFailedError.new("We were expecting #{@actual || 'nil'} to be greater than #{expected} but it's not")
      end
    end

    def to_be_less_than(expected)
      if @actual < expected
        { success: true, message: "Got: #{@actual || 'nil'} (< #{expected})" }
      else
        raise CheckFailedError.new("We were expecting #{@actual || 'nil'} to be less than #{expected} but it's not")
      end
    end

    # Add more expectations as needed
  end

  class CheckFailedError < StandardError; end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
