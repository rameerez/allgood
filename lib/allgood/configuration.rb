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
