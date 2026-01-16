# frozen_string_literal: true

require_relative "../test_helper"
require "rack/test"

# =============================================================================
# This file contains edge case tests that stress-test the allgood gem
# These tests cover unusual inputs, boundary conditions, and error scenarios
# =============================================================================

class EdgeCasesDSLTest < Minitest::Test
  def setup
    Allgood.instance_variable_set(:@configuration, nil)
    @config = Allgood.configuration
  end

  # ==========================================================================
  # Extreme values
  # ==========================================================================

  def test_very_long_check_name
    name = "A" * 10_000
    @config.check(name) { make_sure true }
    assert_equal name, @config.checks.last[:name]
  end

  def test_check_name_with_newlines
    name = "Line1\nLine2\nLine3"
    @config.check(name) { make_sure true }
    assert_equal name, @config.checks.last[:name]
  end

  def test_check_name_with_tabs
    name = "Column1\tColumn2\tColumn3"
    @config.check(name) { make_sure true }
    assert_equal name, @config.checks.last[:name]
  end

  def test_check_name_with_null_byte
    # Null bytes could cause issues in some string processing
    name = "before\x00after"
    @config.check(name) { make_sure true }
    assert_equal name, @config.checks.last[:name]
  end

  def test_registering_1000_checks
    1000.times do |i|
      @config.check("Check #{i}") { make_sure true }
    end
    assert_equal 1000, @config.checks.length
  end

  # ==========================================================================
  # Rate limiting edge cases
  # ==========================================================================

  def test_rate_limit_at_exact_boundary
    @config.check("Boundary", run: "1000 times per day") { make_sure true }
    check = @config.checks.last
    assert_equal 1000, check[:rate][:max_runs]
  end

  def test_rate_limit_with_mixed_case
    @config.check("Mixed", run: "5 TiMeS pEr HoUr") { make_sure true }
    check = @config.checks.last
    assert_equal 5, check[:rate][:max_runs]
    assert_equal "hour", check[:rate][:period]
  end

  def test_rate_limit_singular_time
    @config.check("Singular", run: "1 time per day") { make_sure true }
    check = @config.checks.last
    assert_equal 1, check[:rate][:max_runs]
  end

  # ==========================================================================
  # Condition evaluation edge cases
  # ==========================================================================

  def test_if_condition_with_exception_in_proc
    # If the proc raises an exception, what happens?
    # Current behavior: the exception propagates
    assert_raises(RuntimeError) do
      @config.check("Exception in if", if: -> { raise "boom" }) { make_sure true }
    end
  end

  def test_unless_condition_with_exception_in_proc
    assert_raises(RuntimeError) do
      @config.check("Exception in unless", unless: -> { raise "boom" }) { make_sure true }
    end
  end

  def test_condition_returns_object_instead_of_boolean
    # Any truthy object should work
    @config.check("Object as condition", if: "truthy string") { make_sure true }
    assert_equal :active, @config.checks.last[:status]
  end

  def test_condition_returns_empty_array
    # Empty array is truthy in Ruby
    @config.check("Empty array condition", if: []) { make_sure true }
    assert_equal :active, @config.checks.last[:status]
  end

  def test_condition_returns_zero
    # Zero is truthy in Ruby
    @config.check("Zero condition", if: 0) { make_sure true }
    assert_equal :active, @config.checks.last[:status]
  end

  # ==========================================================================
  # Block edge cases
  # ==========================================================================

  def test_check_block_that_returns_non_hash
    # Check blocks should use make_sure or expect, but what if they return something else?
    @config.check("Returns string") { "just a string" }
    check = @config.checks.last
    assert_equal :active, check[:status]
    # The block is stored but execution handles it
  end

  def test_check_block_with_multiple_make_sure_calls
    result = @config.run_check do
      make_sure true, "First"
      make_sure true, "Second"
      make_sure true, "Third"
    end
    # Only the last result matters
    assert_equal "Third", result[:message]
  end

  # ==========================================================================
  # Expectation edge cases
  # ==========================================================================

  def test_expect_with_nan
    # NaN comparisons are special: NaN != NaN
    nan = Float::NAN
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(nan).to_eq(nan)
    end
    # NaN is not equal to itself
    assert_kind_of Allgood::CheckFailedError, error
  end

  def test_expect_with_infinity
    inf = Float::INFINITY
    result = Allgood::Expectation.new(inf).to_eq(inf)
    assert result[:success]
  end

  def test_expect_greater_than_with_infinity
    result = Allgood::Expectation.new(Float::INFINITY).to_be_greater_than(999_999_999)
    assert result[:success]
  end

  def test_expect_less_than_with_negative_infinity
    result = Allgood::Expectation.new(-Float::INFINITY).to_be_less_than(-999_999_999)
    assert result[:success]
  end

  def test_expect_with_rational_numbers
    # Ruby can handle Rational numbers
    result = Allgood::Expectation.new(Rational(1, 3)).to_eq(Rational(1, 3))
    assert result[:success]
  end

  def test_expect_with_complex_numbers
    # Complex numbers can be compared with ==
    result = Allgood::Expectation.new(Complex(1, 2)).to_eq(Complex(1, 2))
    assert result[:success]
  end

  def test_expect_greater_than_with_string_raises
    # Comparing numbers with strings should fail
    assert_raises(ArgumentError) do
      Allgood::Expectation.new(5).to_be_greater_than("string")
    end
  end

  # ==========================================================================
  # Configuration state edge cases
  # ==========================================================================

  def test_changing_default_timeout_after_checks_added
    @config.check("Before change") { make_sure true }
    @config.default_timeout = 100
    @config.check("After change") { make_sure true }

    # First check should have old default
    assert_equal 10, @config.checks[0][:timeout]
    # Second check should have new default
    assert_equal 100, @config.checks[1][:timeout]
  end

  def test_configuration_is_singleton
    config1 = Allgood.configuration
    config2 = Allgood.configuration
    config1.check("Test") { make_sure true }

    assert_equal 1, config2.checks.length
    assert_same config1, config2
  end

  def test_resetting_configuration
    @config.check("Test") { make_sure true }
    assert_equal 1, @config.checks.length

    # Reset
    Allgood.instance_variable_set(:@configuration, nil)
    new_config = Allgood.configuration

    assert_equal 0, new_config.checks.length
    refute_same @config, new_config
  end
end

class EdgeCasesControllerTest < Minitest::Test
  include Rack::Test::Methods

  def app
    TEST_ROUTER
  end

  def setup
    Allgood.instance_variable_set(:@configuration, nil)
    @config = Allgood.configuration
    Allgood::CacheStore.instance.send(:initialize)
  end

  # ==========================================================================
  # Response edge cases
  # ==========================================================================

  def test_html_response_with_extremely_long_message
    long_message = "X" * 50_000
    @config.check("Long message") { make_sure true, long_message }

    get "/"
    assert last_response.ok?
    # The response should contain the message (possibly truncated by browser)
    assert_includes last_response.body, "X" * 100 # At least some of it
  end

  def test_json_response_with_extremely_long_message
    long_message = "Y" * 50_000
    @config.check("Long message") { make_sure true, long_message }

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    assert_equal long_message, json["checks"].first["message"]
  end

  def test_check_that_modifies_shared_state
    counter = [0] # Using array to have mutable reference

    @config.check("Incrementer") do
      counter[0] += 1
      make_sure true, "Count: #{counter[0]}"
    end

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    assert_includes json["checks"].first["message"], "Count: 1"

    get "/"
    json = JSON.parse(last_response.body)
    assert_includes json["checks"].first["message"], "Count: 2"
  end

  def test_check_with_sleep_near_timeout_boundary
    @config.check("Almost timeout", timeout: 0.1) do
      sleep 0.05 # Less than timeout
      make_sure true
    end

    get "/"
    assert last_response.ok?
  end

  def test_check_with_very_fast_execution
    @config.check("Instant") { make_sure true }

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    # Duration should be very small but non-negative
    assert json["checks"].first["duration"] >= 0
    assert json["checks"].first["duration"] < 100 # Less than 100ms
  end

  # ==========================================================================
  # Content negotiation edge cases
  # ==========================================================================

  def test_accept_header_with_quality_values
    @config.check("Test") { make_sure true }
    header "Accept", "text/html;q=0.9, application/json;q=1.0"
    get "/"
    # Should prefer JSON based on quality
    assert_includes last_response.content_type, "application/json"
  end

  def test_accept_header_with_wildcard
    @config.check("Test") { make_sure true }
    header "Accept", "*/*"
    get "/"
    # Should default to HTML
    assert last_response.ok?
  end

  # ==========================================================================
  # Unicode and encoding edge cases
  # ==========================================================================

  def test_check_with_emoji_in_name_and_message
    @config.check("Status 🔥💯🚀") { make_sure true, "All systems GO! ✅" }

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Status"
    assert_includes last_response.body, "All systems GO!"
  end

  def test_check_with_rtl_text
    @config.check("Hebrew: שלום") { make_sure true, "مرحبا Arabic" }

    get "/"
    assert last_response.ok?
  end

  def test_check_with_cjk_characters
    @config.check("日本語テスト") { make_sure true, "中文 한국어" }

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "日本語テスト"
  end
end

class EdgeCasesCacheStoreTest < Minitest::Test
  def setup
    @store = Allgood::CacheStore.instance
    @store.send(:initialize)
  end

  def test_write_and_read_with_very_long_key
    key = "allgood:" + ("x" * 10_000)
    @store.stub(:rails_cache_available?, false) do
      @store.write(key, "value")
      assert_equal "value", @store.read(key)
    end
  end

  def test_write_and_read_with_empty_string_key
    @store.stub(:rails_cache_available?, false) do
      @store.write("", "empty key value")
      assert_equal "empty key value", @store.read("")
    end
  end

  def test_write_large_data_structure
    large_data = {
      nested: {
        deeply: {
          nested: (1..1000).to_a
        }
      }
    }

    @store.stub(:rails_cache_available?, false) do
      @store.write("large", large_data)
      result = @store.read("large")
      assert_equal large_data, result
    end
  end

  def test_overwrite_preserves_type
    @store.stub(:rails_cache_available?, false) do
      @store.write("key", 123)
      assert_kind_of Integer, @store.read("key")

      @store.write("key", "string")
      assert_kind_of String, @store.read("key")

      @store.write("key", [1, 2, 3])
      assert_kind_of Array, @store.read("key")
    end
  end
end

class EdgeCasesTimeZoneTest < Minitest::Test
  def setup
    Allgood.instance_variable_set(:@configuration, nil)
    @config = Allgood.configuration
  end

  def test_rate_limit_period_at_midnight
    travel_to Time.utc(2024, 1, 1, 0, 0, 0) do
      period = @config.send(:current_period, { period: "day" })
      assert_equal "2024-01-01", period
    end
  end

  def test_rate_limit_period_at_end_of_day
    travel_to Time.utc(2024, 1, 1, 23, 59, 59) do
      period = @config.send(:current_period, { period: "day" })
      assert_equal "2024-01-01", period
    end
  end

  def test_next_period_at_year_boundary
    travel_to Time.utc(2024, 12, 31, 23, 59, 59) do
      next_start = @config.send(:next_period_start, { period: "day" })
      assert_equal Time.utc(2025, 1, 1, 0, 0, 0), next_start
    end
  end

  def test_next_period_at_hour_59
    travel_to Time.utc(2024, 6, 15, 14, 59, 59) do
      next_start = @config.send(:next_period_start, { period: "hour" })
      assert_equal Time.utc(2024, 6, 15, 15, 0, 0), next_start
    end
  end

  def test_leap_year_handling
    # Feb 29 in a leap year
    travel_to Time.utc(2024, 2, 29, 12, 0, 0) do
      period = @config.send(:current_period, { period: "day" })
      assert_equal "2024-02-29", period

      next_start = @config.send(:next_period_start, { period: "day" })
      assert_equal Time.utc(2024, 3, 1, 0, 0, 0), next_start
    end
  end
end

class EdgeCasesErrorMessagesTest < Minitest::Test
  def test_check_failed_error_with_empty_message
    error = Allgood::CheckFailedError.new("")
    assert_equal "", error.message
  end

  def test_check_failed_error_with_nil_message
    # In Ruby, passing nil to Exception.new results in the class name as message
    error = Allgood::CheckFailedError.new(nil)
    assert_equal "Allgood::CheckFailedError", error.message
  end

  def test_check_failed_error_with_unicode_message
    error = Allgood::CheckFailedError.new("Error: 错误 🚨")
    assert_equal "Error: 错误 🚨", error.message
  end

  def test_expectation_error_message_with_special_characters
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new("<script>").to_eq("</script>")
    end
    assert_includes error.message, "<script>"
    assert_includes error.message, "</script>"
  end
end
