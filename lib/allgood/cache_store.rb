# frozen_string_literal: true

module Allgood
  class CacheStore
    def self.instance
      @instance ||= new
    end

    def initialize
      @memory_store = {}
    end

    def read(key)
      if rails_cache_available?
        Rails.cache.read(key)
      else
        @memory_store[key]
      end
    end

    def write(key, value)
      if rails_cache_available?
        expiry = key.include?('day') ? 1.day : 1.hour
        Rails.cache.write(key, value, expires_in: expiry)
      else
        @memory_store[key] = value
      end
    end

    def cleanup_old_keys
      return unless rails_cache_available?

      keys_pattern = "allgood:*"
      if Rails.cache.respond_to?(:delete_matched)
        Rails.cache.delete_matched("#{keys_pattern}:*:#{(Time.current - 2.days).strftime('%Y-%m-%d')}*")
      end
    rescue StandardError => e
      Rails.logger.warn "Allgood: Failed to cleanup old cache keys: #{e.message}"
    end

    private

    def rails_cache_available?
      Rails.cache && Rails.cache.respond_to?(:read) && Rails.cache.respond_to?(:write) &&
        Rails.cache.write("allgood_rails_cache_test_ok", "true") &&
        Rails.cache.read("allgood_rails_cache_test_ok") == "true"
    rescue StandardError => e
      Rails.logger.warn "Allgood: Rails.cache not available (#{e.message}), falling back to memory store"
      false
    end
  end
end
