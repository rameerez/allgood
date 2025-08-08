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
    assert_includes text_content(last_response.body), "It's all good"
  end

  def test_json_error_when_any_check_fails
    @config.check("Fail") { expect(1).to_eq(2) }
    header "Accept", "application/json"
    get "/"
    assert_equal 503, last_response.status
    json = JSON.parse(last_response.body)
    assert_equal "error", json["status"]
    refute json["checks"].first["success"]
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
  end
end