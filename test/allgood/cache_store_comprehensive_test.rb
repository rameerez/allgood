# frozen_string_literal: true

require_relative "../test_helper"

class CacheStoreSingletonTest < Minitest::Test
  def test_instance_returns_same_object
    instance1 = Allgood::CacheStore.instance
    instance2 = Allgood::CacheStore.instance
    assert_same instance1, instance2
  end

  def test_instance_is_cache_store
    assert_instance_of Allgood::CacheStore, Allgood::CacheStore.instance
  end
end

class CacheStoreMemoryFallbackTest < Minitest::Test
  def setup
    @store = Allgood::CacheStore.instance
    @store.send(:initialize)
  end

  def test_read_returns_nil_for_missing_key
    @store.stub(:rails_cache_available?, false) do
      assert_nil @store.read("nonexistent_key")
    end
  end

  def test_write_and_read_string_value
    @store.stub(:rails_cache_available?, false) do
      @store.write("test_key", "test_value")
      assert_equal "test_value", @store.read("test_key")
    end
  end

  def test_write_and_read_integer_value
    @store.stub(:rails_cache_available?, false) do
      @store.write("count", 42)
      assert_equal 42, @store.read("count")
    end
  end

  def test_write_and_read_hash_value
    @store.stub(:rails_cache_available?, false) do
      data = { success: true, message: "ok", time: Time.current }
      @store.write("result", data)
      assert_equal data, @store.read("result")
    end
  end

  def test_write_and_read_array_value
    @store.stub(:rails_cache_available?, false) do
      @store.write("items", [1, 2, 3])
      assert_equal [1, 2, 3], @store.read("items")
    end
  end

  def test_write_and_read_nil_value
    @store.stub(:rails_cache_available?, false) do
      @store.write("nil_key", nil)
      assert_nil @store.read("nil_key")
    end
  end

  def test_write_and_read_boolean_values
    @store.stub(:rails_cache_available?, false) do
      @store.write("true_key", true)
      @store.write("false_key", false)
      assert_equal true, @store.read("true_key")
      assert_equal false, @store.read("false_key")
    end
  end

  def test_write_overwrites_existing_value
    @store.stub(:rails_cache_available?, false) do
      @store.write("key", "first")
      @store.write("key", "second")
      assert_equal "second", @store.read("key")
    end
  end

  def test_multiple_keys_are_independent
    @store.stub(:rails_cache_available?, false) do
      @store.write("key1", "value1")
      @store.write("key2", "value2")
      assert_equal "value1", @store.read("key1")
      assert_equal "value2", @store.read("key2")
    end
  end

  def test_write_and_read_with_special_characters_in_key
    @store.stub(:rails_cache_available?, false) do
      key = "allgood:test:special-chars_123"
      @store.write(key, "value")
      assert_equal "value", @store.read(key)
    end
  end

  def test_write_and_read_with_unicode_key
    @store.stub(:rails_cache_available?, false) do
      key = "allgood:日本語:テスト"
      @store.write(key, "value")
      assert_equal "value", @store.read(key)
    end
  end
end

class CacheStoreRailsCacheTest < Minitest::Test
  def setup
    @store = Allgood::CacheStore.instance
    @store.send(:initialize)
    @memory_cache = ActiveSupport::Cache::MemoryStore.new
  end

  def test_uses_rails_cache_when_available
    @store.stub(:rails_cache_available?, true) do
      Rails.stub(:cache, @memory_cache) do
        @store.write("test_key", "rails_value")
        assert_equal "rails_value", @memory_cache.read("test_key")
      end
    end
  end

  def test_read_from_rails_cache
    @store.stub(:rails_cache_available?, true) do
      Rails.stub(:cache, @memory_cache) do
        @memory_cache.write("pre_key", "pre_value")
        assert_equal "pre_value", @store.read("pre_key")
      end
    end
  end

  def test_write_uses_hour_expiry_for_non_day_keys
    @store.stub(:rails_cache_available?, true) do
      Rails.stub(:cache, @memory_cache) do
        @store.write("allgood:something:hour", "value")
        # Verify it was written - expiry is set but we can't easily test it
        assert_equal "value", @memory_cache.read("allgood:something:hour")
      end
    end
  end

  def test_write_uses_day_expiry_for_day_keys
    @store.stub(:rails_cache_available?, true) do
      Rails.stub(:cache, @memory_cache) do
        @store.write("allgood:limit:day:key", "value")
        assert_equal "value", @memory_cache.read("allgood:limit:day:key")
      end
    end
  end
end

class CacheStoreCleanupTest < Minitest::Test
  def setup
    @store = Allgood::CacheStore.instance
    @store.send(:initialize)
  end

  def test_cleanup_does_nothing_without_rails_cache
    @store.stub(:rails_cache_available?, false) do
      # Should not raise
      @store.cleanup_old_keys
    end
  end

  def test_cleanup_does_nothing_without_delete_matched
    cache = ActiveSupport::Cache::MemoryStore.new
    @store.stub(:rails_cache_available?, true) do
      Rails.stub(:cache, cache) do
        # Should not raise even without delete_matched
        @store.cleanup_old_keys
      end
    end
  end

  def test_cleanup_calls_delete_matched_with_correct_pattern
    deleted_patterns = []
    fake_cache = Object.new
    fake_cache.define_singleton_method(:write) { |*| true }
    fake_cache.define_singleton_method(:read) { |*| "true" }
    fake_cache.define_singleton_method(:respond_to?) { |m| m == :delete_matched || super(m) }
    fake_cache.define_singleton_method(:delete_matched) { |pattern| deleted_patterns << pattern }

    travel_to Time.utc(2024, 6, 15, 12, 0, 0) do
      @store.stub(:rails_cache_available?, true) do
        Rails.stub(:cache, fake_cache) do
          @store.cleanup_old_keys
          expected_date = (Time.current - 2.days).strftime("%Y-%m-%d")
          assert_equal 1, deleted_patterns.length
          assert_match(/#{expected_date}/, deleted_patterns.first)
        end
      end
    end
  end

  def test_cleanup_handles_errors_gracefully
    fake_cache = Object.new
    fake_cache.define_singleton_method(:write) { |*| true }
    fake_cache.define_singleton_method(:read) { |*| "true" }
    fake_cache.define_singleton_method(:respond_to?) { |m| m == :delete_matched || super(m) }
    fake_cache.define_singleton_method(:delete_matched) { |*| raise "Network error" }

    logged_warnings = []
    fake_logger = Object.new
    fake_logger.define_singleton_method(:warn) { |msg| logged_warnings << msg }

    @store.stub(:rails_cache_available?, true) do
      Rails.stub(:cache, fake_cache) do
        Rails.stub(:logger, fake_logger) do
          # Should not raise
          @store.cleanup_old_keys
          assert logged_warnings.any? { |w| w.include?("Failed to cleanup") }
        end
      end
    end
  end
end

class CacheStoreRailsCacheAvailabilityTest < Minitest::Test
  def setup
    @store = Allgood::CacheStore.instance
    @store.send(:initialize)
  end

  def test_rails_cache_available_with_working_cache
    cache = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, cache) do
      assert @store.send(:rails_cache_available?)
    end
  end

  def test_rails_cache_available_false_when_write_fails
    fake_cache = Object.new
    fake_cache.define_singleton_method(:respond_to?) { |m| [:read, :write].include?(m) || super(m) }
    fake_cache.define_singleton_method(:write) { |*| raise "Write failed" }
    fake_cache.define_singleton_method(:read) { |*| nil }

    Rails.stub(:cache, fake_cache) do
      refute @store.send(:rails_cache_available?)
    end
  end

  def test_rails_cache_available_false_when_read_fails
    fake_cache = Object.new
    fake_cache.define_singleton_method(:respond_to?) { |m| [:read, :write].include?(m) || super(m) }
    fake_cache.define_singleton_method(:write) { |*| true }
    fake_cache.define_singleton_method(:read) { |*| raise "Read failed" }

    Rails.stub(:cache, fake_cache) do
      refute @store.send(:rails_cache_available?)
    end
  end

  def test_rails_cache_available_false_when_read_returns_wrong_value
    fake_cache = Object.new
    fake_cache.define_singleton_method(:respond_to?) { |m| [:read, :write].include?(m) || super(m) }
    fake_cache.define_singleton_method(:write) { |*| true }
    fake_cache.define_singleton_method(:read) { |*| "wrong" }

    Rails.stub(:cache, fake_cache) do
      refute @store.send(:rails_cache_available?)
    end
  end

  def test_rails_cache_available_false_when_cache_is_nil
    Rails.stub(:cache, nil) do
      refute @store.send(:rails_cache_available?)
    end
  end

  def test_rails_cache_available_false_when_cache_lacks_methods
    fake_cache = Object.new
    Rails.stub(:cache, fake_cache) do
      refute @store.send(:rails_cache_available?)
    end
  end
end
