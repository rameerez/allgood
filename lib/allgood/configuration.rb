module Allgood
  class Configuration
    attr_reader :checks
    attr_accessor :default_timeout

    def initialize
      @checks = []
      @default_timeout = 10 # Default timeout of 10 seconds
    end

    def check(name, **options, &block)
      # Handle environment-specific options
      if options[:only]
        environments = Array(options[:only])
        return unless environments.include?(Rails.env.to_sym)
      end

      if options[:except]
        environments = Array(options[:except])
        return if environments.include?(Rails.env.to_sym)
      end

      # Handle conditional checks
      if options[:if]
        condition = options[:if]
        return unless condition.is_a?(Proc) ? condition.call : condition
      end

      if options[:unless]
        condition = options[:unless]
        return if condition.is_a?(Proc) ? condition.call : condition
      end

      # Set timeout (default or custom)
      timeout = options[:timeout] || @default_timeout

      @checks << {
        name: name,
        block: block,
        timeout: timeout,
        options: options
      }
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
