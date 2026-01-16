# frozen_string_literal: true

require_relative "../test_helper"

class ConfigurationRateLimitTest < Minitest::Test
  def setup
    Allgood.instance_variable_set(:@configuration, nil)
    @config = Allgood.configuration
  end

  def test_parse_run_frequency_valid_day
    rate = @config.send(:parse_run_frequency, "2 times per day")
    assert_equal({ max_runs: 2, period: "day" }, rate)
  end

  def test_parse_run_frequency_valid_hour
    rate = @config.send(:parse_run_frequency, "3 times per hour")
    assert_equal({ max_runs: 3, period: "hour" }, rate)
  end

  def test_parse_run_frequency_invalid_format
    error = assert_raises(ArgumentError) { @config.send(:parse_run_frequency, "every now and then") }
    assert_match(/Unsupported frequency format/, error.message)
  end

  def test_parse_run_frequency_invalid_number
    error = assert_raises(ArgumentError) { @config.send(:parse_run_frequency, "0 times per day") }
    assert_match(/positive/, error.message)
  end

  def test_parse_run_frequency_too_large
    error = assert_raises(ArgumentError) { @config.send(:parse_run_frequency, "1001 times per hour") }
    assert_match(/Maximum 1000/, error.message)
  end

  def test_should_run_check_without_rate
    check = { name: "No rate", block: proc {}, status: :active }
    assert @config.should_run_check?(check)
  end

  def test_should_run_check_resets_on_new_period
    travel_to Time.utc(2020,1,1,0,0,0) do
      check = { name: "limited", block: proc {}, status: :active, rate: { max_runs: 1, period: "hour" } }
      assert @config.should_run_check?(check)
      refute @config.should_run_check?(check)

      travel 61.minutes
      assert @config.should_run_check?(check), "Should reset runs count on new hour"
    end
  end

  def test_should_run_check_sets_skip_reason_and_retains_last_result
    check = { name: "limited", block: proc {}, status: :active, rate: { max_runs: 1, period: "hour" } }
    assert @config.should_run_check?(check)
    # write last result success to cache to be used by controller
    Allgood::CacheStore.instance.write("allgood:last_result:limited", { success: true, message: "ok", time: Time.current })
    refute @config.should_run_check?(check)
    assert_match(/Rate limited/, check[:skip_reason])
  end

  def test_should_run_check_waits_until_next_period_after_error
    check = { name: "API", block: proc {}, status: :active, rate: { max_runs: 5, period: "hour" } }
    Allgood::CacheStore.instance.write("allgood:error:api", "Error: boom")
    refute @config.should_run_check?(check)
    assert_match(/Waiting until/, check[:skip_reason])
  end
end