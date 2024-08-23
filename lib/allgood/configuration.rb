module Allgood
  class Configuration
    attr_reader :checks

    def initialize
      @checks = []
    end

    def check(name, &block)
      @checks << { name: name, block: block }
    end
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
