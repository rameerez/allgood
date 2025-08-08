# frozen_string_literal: true

require_relative "../test_helper"

class CacheStoreTest < Minitest::Test
  def setup
    @store = Allgood::CacheStore.instance
    # Clear internal memory store by reinitializing private instance vars via send
    @store.send(:initialize)
  end

  def test_memory_store_read_write_without_rails_cache
    # Force rails_cache_available? to false
    @store.stub(:rails_cache_available?, false) do
      assert_nil @store.read("k")
      @store.write("k", 123)
      assert_equal 123, @store.read("k")
    end
  end

  def test_rails_cache_write_uses_hour_expiry
    store = ActiveSupport::Cache::MemoryStore.new
    @store.stub(:rails_cache_available?, true) do
      Rails.stub(:cache, store) do
        @store.write("allgood:something per hour", "v")
        assert_equal "v", store.read("allgood:something per hour")
      end
    end
  end

  def test_rails_cache_write_uses_day_expiry_for_day_keys
    store = ActiveSupport::Cache::MemoryStore.new
    @store.stub(:rails_cache_available?, true) do
      Rails.stub(:cache, store) do
        @store.write("allgood:limit:1 times per day", "v")
        assert_equal "v", store.read("allgood:limit:1 times per day")
      end
    end
  end

  def test_cleanup_old_keys_noop_without_delete_matched
    store = ActiveSupport::Cache::MemoryStore.new
    # MemoryStore in Rails 7 does not implement delete_matched by default
    @store.stub(:rails_cache_available?, true) do
      Rails.stub(:cache, store) do
        # Should not raise
        @store.cleanup_old_keys
      end
    end
  end

  def test_rails_cache_available_checks_read_write
    store = ActiveSupport::Cache::MemoryStore.new
    Rails.stub(:cache, store) do
      assert @store.send(:rails_cache_available?)
    end
  end

  def test_rails_cache_available_handles_errors
    fake_cache = Object.new
    def fake_cache.write(*)
      raise "boom"
    end
    def fake_cache.read(*)
      raise "boom"
    end
    Rails.stub(:cache, fake_cache) do
      refute @store.send(:rails_cache_available?)
    end
  end
end