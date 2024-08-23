module Allgood
  class Configuration
    attr_reader :checks
    attr_accessor :default_timeout

    def initialize
      @checks = []
      @default_timeout = 10 # Default timeout of 10 seconds
    end

    def check(name, &block)
      @checks << { name: name, block: block, timeout: @default_timeout }
    end

    def run_check(&block)
      CheckRunner.new.instance_eval(&block)
    end
  end

  class CheckRunner
    def make_sure(condition)
      raise CheckFailedError, "Check failed" unless condition
      true
    end
  end

  class CheckFailedError < StandardError; end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
