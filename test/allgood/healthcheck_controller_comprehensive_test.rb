# frozen_string_literal: true

require_relative "../test_helper"
require "rack/test"

class HealthcheckControllerComprehensiveTest < Minitest::Test
  include Rack::Test::Methods

  def app
    TEST_ROUTER
  end

  def setup
    Allgood.instance_variable_set(:@configuration, nil)
    @config = Allgood.configuration
    # Reset the cache store
    Allgood::CacheStore.instance.send(:initialize)
  end

  def text_content(html)
    Nokogiri::HTML.parse(html).text
  end

  # ==========================================================================
  # Empty configuration
  # ==========================================================================

  def test_html_with_no_checks_configured
    # No checks registered
    get "/"
    assert last_response.ok?
    doc = Nokogiri::HTML.parse(last_response.body)
    assert_includes doc.text, "No health checks were run"
  end

  def test_json_with_no_checks_configured
    header "Accept", "application/json"
    get "/"
    assert last_response.ok?
    json = JSON.parse(last_response.body)
    assert_equal "ok", json["status"]
    assert_empty json["checks"]
  end

  # ==========================================================================
  # Single check scenarios
  # ==========================================================================

  def test_single_passing_check
    @config.check("DB Connection") { make_sure true, "Connected" }
    get "/"
    assert last_response.ok?
    assert_includes text_content(last_response.body), "DB Connection"
    assert_includes text_content(last_response.body), "Connected"
  end

  def test_single_failing_check
    @config.check("Service check") { make_sure false, "Service unavailable" }
    get "/"
    assert_equal 503, last_response.status
    assert_includes text_content(last_response.body), "Something's wrong"
  end

  def test_single_skipped_check
    @config.check("Conditional", if: false) { make_sure true }
    get "/"
    assert last_response.ok?
    doc = Nokogiri::HTML.parse(last_response.body)
    assert doc.css(".skipped").any?
  end

  # ==========================================================================
  # Multiple check scenarios
  # ==========================================================================

  def test_all_checks_passing
    @config.check("Check 1") { make_sure true }
    @config.check("Check 2") { expect(5).to_eq(5) }
    @config.check("Check 3") { expect(10).to_be_greater_than(5) }

    get "/"
    assert last_response.ok?
    doc = Nokogiri::HTML.parse(last_response.body)
    # All should have success emojis
    assert_equal 3, doc.css(".check").count { |c| c.text.include?("") }
  end

  def test_mix_of_passing_and_failing
    @config.check("Pass 1") { make_sure true }
    @config.check("Fail 1") { make_sure false }
    @config.check("Pass 2") { make_sure true }

    get "/"
    assert_equal 503, last_response.status
    doc = Nokogiri::HTML.parse(last_response.body)
    assert doc.css(".check").any? { |c| c.text.include?("") }
    assert doc.css(".check").any? { |c| c.text.include?("") }
  end

  def test_mix_of_passing_and_skipped
    @config.check("Active") { make_sure true }
    @config.check("Skipped", if: false) { make_sure true }

    get "/"
    assert last_response.ok?
    doc = Nokogiri::HTML.parse(last_response.body)
    assert doc.css(".check").any? { |c| c.text.include?("") }
    assert doc.css(".check.skipped").any?
  end

  def test_all_checks_skipped
    @config.check("Skip 1", if: false) { make_sure true }
    @config.check("Skip 2", if: false) { make_sure true }

    get "/"
    assert last_response.ok? # Skipped checks count as success
    doc = Nokogiri::HTML.parse(last_response.body)
    assert_equal 2, doc.css(".check.skipped").count
  end

  def test_mix_of_passing_failing_and_skipped
    @config.check("Pass") { make_sure true }
    @config.check("Fail") { make_sure false }
    @config.check("Skip", if: false) { make_sure true }

    get "/"
    assert_equal 503, last_response.status
    doc = Nokogiri::HTML.parse(last_response.body)
    checks = doc.css(".check")
    assert_equal 3, checks.count
  end

  # ==========================================================================
  # Check ordering
  # ==========================================================================

  def test_checks_appear_in_defined_order
    @config.check("First") { make_sure true }
    @config.check("Second") { make_sure true }
    @config.check("Third") { make_sure true }

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    names = json["checks"].map { |c| c["name"] }
    assert_equal %w[First Second Third], names
  end

  # ==========================================================================
  # Error types handling
  # ==========================================================================

  def test_timeout_error_is_handled
    @config.check("Slow check", timeout: 0.01) do
      sleep 0.1
      make_sure true
    end

    get "/"
    assert_equal 503, last_response.status
    assert_includes text_content(last_response.body), "timed out"
  end

  def test_check_failed_error_is_handled
    @config.check("Failed check") { make_sure false, "Custom failure message" }

    get "/"
    assert_equal 503, last_response.status
    assert_includes text_content(last_response.body), "Custom failure message"
  end

  def test_standard_error_in_check_is_handled
    @config.check("Error check") do
      raise "Unexpected error"
    end

    get "/"
    assert_equal 503, last_response.status
    assert_includes text_content(last_response.body), "Error:"
    assert_includes text_content(last_response.body), "Unexpected error"
  end

  def test_argument_error_in_check_is_handled
    @config.check("Argument error check") do
      raise ArgumentError, "Bad argument"
    end

    get "/"
    assert_equal 503, last_response.status
    assert_includes text_content(last_response.body), "Bad argument"
  end

  def test_type_error_in_comparison
    @config.check("Type error check") do
      expect(nil).to_be_greater_than(5)
    end

    get "/"
    assert_equal 503, last_response.status
    assert_includes text_content(last_response.body), "Error:"
  end

  # ==========================================================================
  # Duration tracking
  # ==========================================================================

  def test_duration_is_recorded
    @config.check("Fast check") { make_sure true }

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    duration = json["checks"].first["duration"]
    assert_kind_of Numeric, duration
    assert duration >= 0
  end

  def test_duration_reflects_execution_time
    @config.check("Slow check") do
      sleep 0.05
      make_sure true
    end

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    duration = json["checks"].first["duration"]
    assert duration >= 50, "Duration should be at least 50ms"
  end

  def test_skipped_checks_have_zero_duration
    @config.check("Skipped", if: false) { make_sure true }

    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    assert_equal 0, json["checks"].first["duration"]
  end

  # ==========================================================================
  # HTML response structure
  # ==========================================================================

  def test_html_header_shows_all_good_when_passing
    @config.check("Pass") { make_sure true }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    header = doc.at_css("header h1")
    assert_includes header.text, "all good"
  end

  def test_html_header_shows_error_when_failing
    @config.check("Fail") { make_sure false }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    header = doc.at_css("header h1")
    assert_includes header.text, "Something's wrong"
  end

  def test_html_includes_check_name_in_bold
    @config.check("Important Check") { make_sure true }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    bold = doc.at_css(".check b")
    assert_equal "Important Check", bold.text
  end

  def test_html_includes_message_in_italics
    @config.check("Test") { make_sure true, "All systems go" }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    italic = doc.at_css(".check i")
    assert_includes italic.text, "All systems go"
  end

  def test_html_includes_duration_in_code_tag
    @config.check("Test") { make_sure true }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    code = doc.at_css(".check code")
    assert_match(/\[\d+(\.\d+)?ms\]/, code.text)
  end

  def test_html_skipped_checks_have_skipped_class
    @config.check("Skipped", if: false) { make_sure true }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    assert doc.at_css(".check.skipped")
  end

  def test_html_skipped_checks_show_skip_emoji
    @config.check("Skipped", if: false) { make_sure true }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    skipped_check = doc.at_css(".check.skipped")
    assert_includes skipped_check.text, ""
  end

  def test_html_skipped_checks_do_not_show_duration
    @config.check("Skipped", if: false) { make_sure true }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    skipped_check = doc.at_css(".check.skipped")
    refute skipped_check.at_css("code")
  end

  # ==========================================================================
  # JSON response structure
  # ==========================================================================

  def test_json_has_status_key
    @config.check("Test") { make_sure true }
    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    assert json.key?("status")
  end

  def test_json_has_checks_array
    @config.check("Test") { make_sure true }
    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    assert_kind_of Array, json["checks"]
  end

  def test_json_check_has_required_keys
    @config.check("Test") { make_sure true, "Message" }
    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    check = json["checks"].first
    assert check.key?("name")
    assert check.key?("success")
    assert check.key?("message")
    assert check.key?("duration")
  end

  def test_json_skipped_check_has_skipped_key
    @config.check("Skipped", if: false) { make_sure true }
    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    check = json["checks"].first
    assert_equal true, check["skipped"]
  end

  def test_json_status_ok_when_all_pass
    @config.check("Test") { make_sure true }
    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    assert_equal "ok", json["status"]
  end

  def test_json_status_error_when_any_fail
    @config.check("Test") { make_sure false }
    header "Accept", "application/json"
    get "/"
    json = JSON.parse(last_response.body)
    assert_equal "error", json["status"]
  end

  # ==========================================================================
  # XSS prevention
  # ==========================================================================

  def test_html_escapes_script_tags_in_name
    @config.check("<script>alert('xss')</script>") { make_sure true }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    # The script tag should be escaped and not executed
    refute doc.at_css("body script")
    # But the text should be visible
    assert_includes doc.text, "<script>"
  end

  def test_html_escapes_script_tags_in_message
    @config.check("Test") { make_sure true, "<script>alert('xss')</script>" }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    refute doc.at_css("body script")
  end

  def test_html_escapes_html_entities
    @config.check("Test <b>bold</b>") { make_sure true, "Message with <i>html</i>" }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    name_b = doc.at_css(".check b")
    assert_includes name_b.text, "<b>bold</b>"
    # Should not be rendered as bold
    refute name_b.at_css("b")
  end

  # ==========================================================================
  # HTTP status codes
  # ==========================================================================

  def test_200_when_all_pass
    @config.check("Pass") { make_sure true }
    get "/"
    assert_equal 200, last_response.status
  end

  def test_503_when_any_fail
    @config.check("Fail") { make_sure false }
    get "/"
    assert_equal 503, last_response.status
  end

  def test_200_when_all_skipped
    @config.check("Skip", if: false) { make_sure true }
    get "/"
    assert_equal 200, last_response.status
  end

  def test_500_on_internal_error
    Allgood.stub(:configuration, nil) do
      get "/"
      assert_equal 500, last_response.status
    end
  end

  # ==========================================================================
  # Content type negotiation
  # ==========================================================================

  def test_html_response_by_default
    @config.check("Test") { make_sure true }
    get "/"
    assert_includes last_response.content_type, "text/html"
  end

  def test_json_response_when_requested
    @config.check("Test") { make_sure true }
    header "Accept", "application/json"
    get "/"
    assert_includes last_response.content_type, "application/json"
  end

  # ==========================================================================
  # Check messages
  # ==========================================================================

  def test_passing_check_shows_custom_message
    @config.check("Test") { make_sure true, "Custom success message" }
    get "/"
    assert_includes text_content(last_response.body), "Custom success message"
  end

  def test_failing_check_shows_custom_message
    @config.check("Test") { make_sure false, "Custom failure message" }
    get "/"
    assert_includes text_content(last_response.body), "Custom failure message"
  end

  def test_expect_eq_shows_value_in_message
    @config.check("Test") { expect(42).to_eq(42) }
    get "/"
    assert_includes text_content(last_response.body), "42"
  end

  def test_expect_greater_than_shows_comparison_in_message
    @config.check("Test") { expect(10).to_be_greater_than(5) }
    get "/"
    assert_includes text_content(last_response.body), "10"
    assert_includes text_content(last_response.body), "> 5"
  end

  # ==========================================================================
  # Concurrent requests (simulated)
  # ==========================================================================

  def test_multiple_sequential_requests_work
    @config.check("Test") { make_sure true }
    3.times do
      get "/"
      assert last_response.ok?
    end
  end
end
