# frozen_string_literal: true

require_relative "../test_helper"
require "rack/test"

class IntegrationTest < Minitest::Test
  include Rack::Test::Methods

  def app
    TEST_ROUTER
  end

  def setup
    Allgood.instance_variable_set(:@configuration, nil)
    Allgood::CacheStore.instance.send(:initialize)
  end

  # ==========================================================================
  # Full DSL integration - Real-world scenarios
  # ==========================================================================

  def test_realistic_health_check_configuration
    config = Allgood.configuration

    # Simulate a typical production config
    config.check("Database connection") do
      # Simulating a DB check
      make_sure true, "Connected to database"
    end

    config.check("Cache working") do
      # Simulating a cache check
      make_sure true, "Cache read/write successful"
    end

    config.check("Disk space below 90%") do
      usage = 75 # Simulated
      expect(usage).to_be_less_than(90)
    end

    get "/"
    assert last_response.ok?

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    assert_equal "ok", json["status"]
    assert_equal 3, json["checks"].length
  end

  def test_check_with_business_metrics
    config = Allgood.configuration

    config.check("Recent signups exist") do
      signups = 5 # Simulated count
      expect(signups).to_be_greater_than(0)
    end

    config.check("Orders within expected range") do
      orders = 150 # Simulated
      make_sure orders > 100 && orders < 1000, "Orders count: #{orders}"
    end

    get "/"
    assert last_response.ok?
  end

  def test_mixed_environment_checks
    config = Allgood.configuration

    # This check always runs
    config.check("Always run") { make_sure true }

    # This check only runs in production (we're in test, so skipped)
    Rails.stub(:env, ActiveSupport::StringInquirer.new("test")) do
      config.check("Production only", only: :production) { make_sure true }
    end

    # This check has a condition
    config.check("Conditional", if: true) { make_sure true }

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)

    assert_equal 3, json["checks"].length
    assert json["checks"].any? { |c| c["skipped"] }
    assert json["checks"].count { |c| !c["skipped"] } == 2
  end

  # ==========================================================================
  # Error handling integration
  # ==========================================================================

  def test_single_failure_marks_entire_response_as_error
    config = Allgood.configuration

    config.check("Pass 1") { make_sure true }
    config.check("Pass 2") { make_sure true }
    config.check("Fail") { make_sure false }
    config.check("Pass 3") { make_sure true }

    get "/"
    assert_equal 503, last_response.status

    doc = Nokogiri::HTML.parse(last_response.body)
    assert_includes doc.at_css("header h1").text, "Something's wrong"
  end

  def test_timeout_affects_only_that_check
    config = Allgood.configuration

    config.check("Fast check") { make_sure true }
    config.check("Slow check", timeout: 0.01) do
      sleep 0.1
      make_sure true
    end
    config.check("Another fast check") { make_sure true }

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)

    # Should have 3 checks
    assert_equal 3, json["checks"].length

    # First should pass
    assert json["checks"][0]["success"]

    # Second should fail (timeout)
    refute json["checks"][1]["success"]
    assert_includes json["checks"][1]["message"], "timed out"

    # Third should pass
    assert json["checks"][2]["success"]
  end

  # ==========================================================================
  # Rate limiting integration
  # ==========================================================================

  def test_rate_limiting_works_across_multiple_requests
    config = Allgood.configuration

    runs = 0
    config.check("Limited API", run: "2 times per hour") do
      runs += 1
      make_sure true, "Run #{runs}"
    end

    # First request - should run
    get "/"
    assert last_response.ok?
    assert_equal 1, runs

    # Second request - should run
    get "/"
    assert last_response.ok?
    assert_equal 2, runs

    # Third request - should be rate limited
    get "/"
    assert last_response.ok?
    # Should still be 2 (rate limited)
    assert_equal 2, runs
    assert_includes text_content(last_response.body), "Rate limited"
  end

  def test_rate_limited_check_shows_last_result
    config = Allgood.configuration

    config.check("Limited", run: "1 time per hour") do
      make_sure true, "API responded successfully"
    end

    # First run
    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    first_check = json["checks"].first
    assert first_check["success"]
    refute first_check["skipped"]

    # Second run - rate limited
    get "/"
    json = JSON.parse(last_response.body)
    second_check = json["checks"].first
    assert second_check["success"]
    assert second_check["skipped"]
    assert_includes second_check["message"], "Rate limited"
  end

  # ==========================================================================
  # Expectation chaining integration
  # ==========================================================================

  def test_expect_to_eq_in_check
    config = Allgood.configuration

    config.check("Equality check") do
      value = 42
      expect(value).to_eq(42)
    end

    get "/"
    assert last_response.ok?
  end

  def test_expect_to_be_greater_than_in_check
    config = Allgood.configuration

    config.check("Greater than check") do
      count = 100
      expect(count).to_be_greater_than(50)
    end

    get "/"
    assert last_response.ok?
  end

  def test_expect_to_be_less_than_in_check
    config = Allgood.configuration

    config.check("Less than check") do
      usage = 75
      expect(usage).to_be_less_than(90)
    end

    get "/"
    assert last_response.ok?
  end

  def test_multiple_expectations_in_single_check
    config = Allgood.configuration

    config.check("Multiple expectations") do
      value = 50
      make_sure value > 0, "Value is positive"
      expect(value).to_be_greater_than(10)
      expect(value).to_be_less_than(100)
    end

    get "/"
    assert last_response.ok?
  end

  # ==========================================================================
  # Custom timeout integration
  # ==========================================================================

  def test_custom_timeout_per_check
    config = Allgood.configuration

    config.check("Fast check", timeout: 5) { make_sure true }
    config.check("Slow check", timeout: 30) { make_sure true }

    header "Accept", "application/json"
    get "/"
    assert last_response.ok?
  end

  def test_default_timeout_can_be_changed
    config = Allgood.configuration
    config.default_timeout = 20

    config.check("Check 1") { make_sure true }
    config.check("Check 2", timeout: 5) { make_sure true }

    # First check should use default (20)
    assert_equal 20, config.checks[0][:timeout]
    # Second check should use custom (5)
    assert_equal 5, config.checks[1][:timeout]
  end

  # ==========================================================================
  # Edge cases
  # ==========================================================================

  def test_check_with_nil_return_value
    config = Allgood.configuration

    config.check("Nil return") do
      result = nil
      make_sure !result.nil? || result.nil?, "Handled nil"
    end

    get "/"
    assert last_response.ok?
  end

  def test_check_with_exception_recovery
    config = Allgood.configuration

    config.check("Exception check") do
      begin
        raise "Simulated error"
      rescue StandardError => e
        make_sure e.message == "Simulated error", "Caught expected error"
      end
    end

    get "/"
    assert last_response.ok?
  end

  def test_check_with_unicode_content
    config = Allgood.configuration

    config.check("Unicode test 日本語") do
      make_sure true, "Success! 成功 🎉"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "日本語"
    assert_includes last_response.body, "成功"
  end

  def test_many_checks_performance
    config = Allgood.configuration

    50.times do |i|
      config.check("Check #{i}") { make_sure true }
    end

    start_time = Time.now
    get "/"
    duration = Time.now - start_time

    assert last_response.ok?
    # Should complete in reasonable time (less than 5 seconds)
    assert duration < 5, "50 checks took too long: #{duration}s"
  end

  private

  def text_content(html)
    Nokogiri::HTML.parse(html).text
  end
end

class DSLIntegrationTest < Minitest::Test
  def setup
    Allgood.instance_variable_set(:@configuration, nil)
  end

  def test_configure_block_style
    Allgood.configure do |config|
      config.check("Via configure") { make_sure true }
    end

    assert_equal 1, Allgood.configuration.checks.length
  end

  def test_direct_configuration_access
    Allgood.configuration.check("Direct access") { make_sure true }

    assert_equal 1, Allgood.configuration.checks.length
  end

  def test_mixed_configuration_styles
    Allgood.configure do |config|
      config.check("Via configure") { make_sure true }
    end

    Allgood.configuration.check("Direct access") { make_sure true }

    assert_equal 2, Allgood.configuration.checks.length
  end
end
