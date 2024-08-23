module Allgood
  class Configuration
    attr_reader :checks
    attr_accessor :default_timeout

    def initialize
      @checks = []
      @default_timeout = 10 # Default timeout of 10 seconds
    end

    def check(name, timeout: nil, &block)
      @checks << { name: name, block: block, timeout: timeout || @default_timeout }
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
