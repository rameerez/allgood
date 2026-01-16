# frozen_string_literal: true

require_relative "../test_helper"
require "rack/test"

class HealthcheckControllerTest < Minitest::Test
  include Rack::Test::Methods

  def app
    TEST_ROUTER
  end

  def setup
    Allgood.instance_variable_set(:@configuration, nil)
    @config = Allgood.configuration
  end

  def text_content(html)
    Nokogiri::HTML.parse(html).text
  end

  def test_html_ok_when_all_checks_pass
    @config.check("Pass 1") { make_sure true }
    @config.check("Pass 2") { expect(1).to_eq(1) }

    get "/"
    assert last_response.ok?, "Expected 200 OK"
    doc = Nokogiri::HTML.parse(last_response.body)
    header_text = doc.at_css('header h1')&.text
    assert_includes header_text, "It's all good"
    # Verify success emojis visible for non-skipped
    check_lines = doc.css('.check').map { |n| n.text }
    assert check_lines.any? { |t| t.include?("✅") }
  end

  def test_html_escapes_check_name_and_message
    @config.check("<script>alert('x')</script>") { make_sure false, "<b>bad</b>" }
    get "/"
    doc = Nokogiri::HTML.parse(last_response.body)
    # Ensure escaped content appears literally
    assert_includes doc.text, "<script>alert('x')</script>"
    assert_includes doc.text, "<b>bad</b>"
    # Raw script tag should not be rendered
    refute doc.at_css('script')
    # The name is wrapped in a <b> by the view; ensure its content is the escaped name
    name_b = doc.at_css('.check b')
    assert_equal "<script>alert('x')</script>", name_b.text
    # The message is inside <i> and should not contain raw <b> elements
    msg_i = doc.at_css('.check i')
    assert_includes msg_i.text, "<b>bad</b>"
    refute msg_i.at_css('b')
  end

  def test_json_error_when_any_check_fails
    @config.check("Fail") { expect(1).to_eq(2) }
    header "Accept", "application/json"
    get "/"
    assert_equal 503, last_response.status
    json = JSON.parse(last_response.body)
    # Detailed schema assertions
    assert_equal %w[checks status], json.keys.sort
    assert_equal "error", json["status"]
    assert_kind_of Array, json["checks"]
    first = json["checks"].first
    assert first.key?("name")
    assert first.key?("success")
    assert first.key?("message")
    assert first.key?("duration")
    assert_includes [true, false], first["success"]
    assert_kind_of Numeric, first["duration"]
  end

  def test_json_schema_for_skipped_check
    Rails.stub(:env, ActiveSupport::StringInquirer.new("test")) do
      @config.check("Only prod", only: :production) { make_sure true }
    end
    header "Accept", "application/json"
    get "/"
    assert_equal 200, last_response.status
    json = JSON.parse(last_response.body)
    skipped = json["checks"].find { |c| c["name"] == "Only prod" }
    assert skipped["success"]
    assert_equal true, skipped["skipped"]
    assert_kind_of String, skipped["message"]
    assert_equal 0, skipped["duration"]
  end

  def test_timeout_is_handled
    @config.check("Timeout", timeout: 0.01) { sleep 0.1; make_sure true }

    get "/"
    assert_equal 503, last_response.status
    assert_includes text_content(last_response.body), "timed out"
  end

  def test_skipped_checks_are_marked
    Rails.stub(:env, ActiveSupport::StringInquirer.new("test")) do
      @config.check("Prod only", only: :production) { make_sure true }
      @config.check("Conditional false", if: false) { make_sure true }
    end

    get "/"
    assert last_response.ok?
    doc = Nokogiri::HTML.parse(last_response.body)
    # Skipped checks have the .skipped class
    assert doc.css('.check.skipped').any?
    assert_includes text_content(last_response.body), "Only runs in"
    assert_includes text_content(last_response.body), "condition not met"
  end

  def test_rate_limited_skips_but_keeps_last_result
    # First run passes and stores last_result
    @config.check("API call", run: "1 times per hour") { make_sure true }
    get "/"
    assert last_response.ok?

    # Second run same hour should be skipped but report last success
    get "/"
    assert last_response.ok?
    assert_includes text_content(last_response.body), "Rate limited"
  end

  def test_rate_limit_resets_next_day
    travel_to Time.utc(2024, 12, 31, 23, 59, 0) do
      @config.check("Daily", run: "1 times per day") { make_sure true }
      get "/" # first run ok
      assert last_response.ok?
      get "/" # rate limited within same day
      assert last_response.ok?
      assert_includes text_content(last_response.body), "Rate limited"

      travel 2.minutes # into next day
      get "/" # should run again
      assert last_response.ok?
      refute_includes text_content(last_response.body), "Rate limited"
    end
  end

  def test_rate_limit_error_persists_across_periods_and_blocks_execution
    travel_to Time.utc(2024, 12, 31, 23, 55, 0) do
      # Define a check that fails first time, then passes after midnight
      attempts = 0
      @config.check("Flaky API", run: "10 times per hour") do
        attempts += 1
        if attempts == 1
          make_sure false, "boom"
        else
          make_sure true, "ok"
        end
      end

      # First run fails and stores error state
      get "/"
      assert_equal 503, last_response.status

      # Subsequent run within same hour should be skipped due to previous error
      get "/"
      assert last_response.ok? || last_response.status == 503
      assert_includes text_content(last_response.body), "Rate limited"

      # Even after period change, previous error should keep the check skipped until success
      travel 10.minutes
      travel_to Time.utc(2025, 1, 1, 0, 5, 0)
      get "/"
      # Still rate limited due to previous error persistence
      assert_includes text_content(last_response.body), "Rate limited"
    end
  end

  def test_error_rescue_returns_500
    # Force an unexpected error in run_checks by stubbing configuration
    Allgood.stub(:configuration, nil) do
      get "/"
      assert_equal 500, last_response.status
      assert_includes text_content(last_response.body), "Something's wrong"
    end
  end

  def test_json_format_ok
    @config.check("Pass") { make_sure true }
    header "Accept", "application/json"
    get "/"
    assert_equal 200, last_response.status
    json = JSON.parse(last_response.body)
    assert_equal "ok", json["status"]
    assert_equal "Pass", json["checks"].first["name"]
    assert_includes [true, false], json["checks"].first["success"]
    assert_kind_of String, json["checks"].first["message"]
    assert_kind_of Numeric, json["checks"].first["duration"]
  end
end