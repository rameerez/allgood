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
        # Determine expiration based on the cache key pattern
        expiry = determine_expiry(key)
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

    def determine_expiry(key)
      # Check if the key is for a daily check
      if key.match?(/:day\z/) || # Matches keys ending with :day
         (key.include?('current_period') && key.end_with?('day')) || # Current period keys for daily checks
         (key.include?('runs_count') && key.include?(':day:')) || # Run counts for daily checks
         (key.include?('last_run') && key.end_with?('day')) || # Last run times for daily checks
         (key.include?('error') && key.end_with?('day')) || # Error states for daily checks
         (key.include?('last_result') && key.end_with?('day')) # Last results for daily checks
        1.day
      else
        1.hour
      end
    end

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
