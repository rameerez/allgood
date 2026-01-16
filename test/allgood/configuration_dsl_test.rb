# frozen_string_literal: true

require_relative "../test_helper"

class ConfigurationDslTest < Minitest::Test
  def setup
    Allgood.instance_variable_set(:@configuration, nil)
    @config = Allgood.configuration
  end

  def test_default_timeout
    assert_equal 10, @config.default_timeout
  end

  def test_check_registers_active_check
    blk = proc { make_sure true }
    @config.check("Active check", &blk)
    check = @config.checks.last
    assert_equal :active, check[:status]
    assert_equal blk, check[:block]
    assert_equal 10, check[:timeout]
  end

  def test_check_custom_timeout
    @config.check("Timed", timeout: 2) { make_sure true }
    assert_equal 2, @config.checks.last[:timeout]
  end

  def test_check_only_environment_skips
    Rails.stub(:env, ActiveSupport::StringInquirer.new("test")) do
      @config.check("Prod only", only: :production) { make_sure true }
    end
    c = @config.checks.last
    assert_equal :skipped, c[:status]
    assert_match(/Only runs in/, c[:skip_reason])
  end

  def test_check_except_environment_skips
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      @config.check("No prod", except: :production) { make_sure true }
    end
    c = @config.checks.last
    assert_equal :skipped, c[:status]
    assert_match(/doesn't run in/, c[:skip_reason])
  end

  def test_check_if_boolean_false_skips
    @config.check("if false", if: false) { make_sure true }
    c = @config.checks.last
    assert_equal :skipped, c[:status]
    assert_match(/condition not met/, c[:skip_reason])
  end

  def test_check_if_proc_false_skips
    @config.check("if proc false", if: -> { false }) { make_sure true }
    c = @config.checks.last
    assert_equal :skipped, c[:status]
  end

  def test_check_unless_boolean_true_skips
    @config.check("unless true", unless: true) { make_sure true }
    c = @config.checks.last
    assert_equal :skipped, c[:status]
    assert_match(/`unless` condition met/, c[:skip_reason])
  end

  def test_run_check_and_expectations
    result = @config.run_check { make_sure 1 == 1 }
    assert_equal true, result[:success]

    result = @config.run_check { expect(5).to_eq(5) }
    assert_equal true, result[:success]

    result = @config.run_check { expect(6).to_be_greater_than(5) }
    assert_equal true, result[:success]

    result = @config.run_check { expect(4).to_be_less_than(5) }
    assert_equal true, result[:success]
  end

  def test_expectations_raise_on_failure
    assert_raises(Allgood::CheckFailedError) { @config.run_check { make_sure false } }
    assert_raises(Allgood::CheckFailedError) { @config.run_check { expect(5).to_eq(6) } }
    assert_raises(Allgood::CheckFailedError) { @config.run_check { expect(5).to_be_greater_than(6) } }
    assert_raises(Allgood::CheckFailedError) { @config.run_check { expect(6).to_be_less_than(5) } }
  end
end