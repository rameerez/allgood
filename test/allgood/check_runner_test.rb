# frozen_string_literal: true

require_relative "../test_helper"

class CheckRunnerTest < Minitest::Test
  def setup
    @runner = Allgood::CheckRunner.new
  end

  # ==========================================================================
  # make_sure - Basic behavior
  # ==========================================================================

  def test_make_sure_with_truthy_condition
    result = @runner.make_sure(true)
    assert_equal true, result[:success]
    assert_equal "Check passed", result[:message]
  end

  def test_make_sure_with_truthy_non_boolean_values
    # Truthy values in Ruby: any non-nil, non-false value
    result = @runner.make_sure(1)
    assert_equal true, result[:success]

    result = @runner.make_sure("string")
    assert_equal true, result[:success]

    result = @runner.make_sure([])
    assert_equal true, result[:success]

    result = @runner.make_sure({})
    assert_equal true, result[:success]

    result = @runner.make_sure(0)
    assert_equal true, result[:success]

    result = @runner.make_sure("")
    assert_equal true, result[:success]
  end

  def test_make_sure_with_false_raises_check_failed_error
    error = assert_raises(Allgood::CheckFailedError) do
      @runner.make_sure(false)
    end
    assert_equal "Check failed", error.message
  end

  def test_make_sure_with_nil_raises_check_failed_error
    error = assert_raises(Allgood::CheckFailedError) do
      @runner.make_sure(nil)
    end
    assert_equal "Check failed", error.message
  end

  # ==========================================================================
  # make_sure - Custom messages
  # ==========================================================================

  def test_make_sure_with_custom_success_message
    result = @runner.make_sure(true, "Database connection established")
    assert_equal true, result[:success]
    assert_equal "Database connection established", result[:message]
  end

  def test_make_sure_with_custom_failure_message
    error = assert_raises(Allgood::CheckFailedError) do
      @runner.make_sure(false, "Database connection failed")
    end
    assert_equal "Database connection failed", error.message
  end

  def test_make_sure_with_nil_message_uses_default
    result = @runner.make_sure(true, nil)
    assert_equal "Check passed", result[:message]

    error = assert_raises(Allgood::CheckFailedError) do
      @runner.make_sure(false, nil)
    end
    assert_equal "Check failed", error.message
  end

  def test_make_sure_with_empty_string_message
    result = @runner.make_sure(true, "")
    assert_equal "", result[:message]
  end

  def test_make_sure_with_special_characters_in_message
    message = "<script>alert('XSS')</script> & special \"chars\""
    result = @runner.make_sure(true, message)
    assert_equal message, result[:message]
  end

  def test_make_sure_with_unicode_message
    message = "Check passed! 🎉 日本語テスト"
    result = @runner.make_sure(true, message)
    assert_equal message, result[:message]
  end

  def test_make_sure_with_very_long_message
    message = "A" * 10_000
    result = @runner.make_sure(true, message)
    assert_equal message, result[:message]
  end

  # ==========================================================================
  # expect - Basic chain creation
  # ==========================================================================

  def test_expect_returns_expectation_object
    expectation = @runner.expect(42)
    assert_instance_of Allgood::Expectation, expectation
  end

  def test_expect_with_various_types
    assert_instance_of Allgood::Expectation, @runner.expect(nil)
    assert_instance_of Allgood::Expectation, @runner.expect(true)
    assert_instance_of Allgood::Expectation, @runner.expect("string")
    assert_instance_of Allgood::Expectation, @runner.expect([1, 2, 3])
    assert_instance_of Allgood::Expectation, @runner.expect({ key: "value" })
    assert_instance_of Allgood::Expectation, @runner.expect(3.14)
  end
end

class ExpectationTest < Minitest::Test
  # ==========================================================================
  # to_eq - Basic equality
  # ==========================================================================

  def test_to_eq_with_equal_integers
    result = Allgood::Expectation.new(5).to_eq(5)
    assert_equal true, result[:success]
    assert_includes result[:message], "5"
  end

  def test_to_eq_with_unequal_integers
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(5).to_eq(10)
    end
    assert_includes error.message, "5"
    assert_includes error.message, "10"
  end

  def test_to_eq_with_equal_strings
    result = Allgood::Expectation.new("hello").to_eq("hello")
    assert_equal true, result[:success]
  end

  def test_to_eq_with_unequal_strings
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new("hello").to_eq("world")
    end
    assert_includes error.message, "hello"
    assert_includes error.message, "world"
  end

  def test_to_eq_with_floats
    result = Allgood::Expectation.new(3.14).to_eq(3.14)
    assert_equal true, result[:success]
  end

  def test_to_eq_with_arrays
    result = Allgood::Expectation.new([1, 2, 3]).to_eq([1, 2, 3])
    assert_equal true, result[:success]
  end

  def test_to_eq_with_hashes
    result = Allgood::Expectation.new({ a: 1 }).to_eq({ a: 1 })
    assert_equal true, result[:success]
  end

  def test_to_eq_with_booleans
    result = Allgood::Expectation.new(true).to_eq(true)
    assert_equal true, result[:success]

    result = Allgood::Expectation.new(false).to_eq(false)
    assert_equal true, result[:success]
  end

  # ==========================================================================
  # to_eq - nil handling
  # ==========================================================================

  def test_to_eq_with_nil_equals_nil
    result = Allgood::Expectation.new(nil).to_eq(nil)
    assert_equal true, result[:success]
    assert_includes result[:message], "nil"
  end

  def test_to_eq_with_nil_actual_vs_non_nil_expected
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(nil).to_eq(5)
    end
    assert_includes error.message, "nil"
    assert_includes error.message, "5"
  end

  def test_to_eq_with_non_nil_actual_vs_nil_expected
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(5).to_eq(nil)
    end
    assert_includes error.message, "5"
  end

  # ==========================================================================
  # to_eq - Edge cases
  # ==========================================================================

  def test_to_eq_with_zero
    result = Allgood::Expectation.new(0).to_eq(0)
    assert_equal true, result[:success]
  end

  def test_to_eq_with_negative_numbers
    result = Allgood::Expectation.new(-5).to_eq(-5)
    assert_equal true, result[:success]
  end

  def test_to_eq_with_empty_string
    result = Allgood::Expectation.new("").to_eq("")
    assert_equal true, result[:success]
  end

  def test_to_eq_with_empty_array
    result = Allgood::Expectation.new([]).to_eq([])
    assert_equal true, result[:success]
  end

  def test_to_eq_with_empty_hash
    result = Allgood::Expectation.new({}).to_eq({})
    assert_equal true, result[:success]
  end

  def test_to_eq_string_vs_integer
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new("5").to_eq(5)
    end
    assert_kind_of Allgood::CheckFailedError, error
  end

  def test_to_eq_integer_vs_float
    # In Ruby, 5 == 5.0 is true
    result = Allgood::Expectation.new(5).to_eq(5.0)
    assert_equal true, result[:success]
  end

  # ==========================================================================
  # to_be_greater_than - Basic comparisons
  # ==========================================================================

  def test_to_be_greater_than_when_greater
    result = Allgood::Expectation.new(10).to_be_greater_than(5)
    assert_equal true, result[:success]
    assert_includes result[:message], "10"
    assert_includes result[:message], "> 5"
  end

  def test_to_be_greater_than_when_equal
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(5).to_be_greater_than(5)
    end
    assert_includes error.message, "5"
  end

  def test_to_be_greater_than_when_less
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(3).to_be_greater_than(5)
    end
    assert_includes error.message, "3"
    assert_includes error.message, "5"
  end

  # ==========================================================================
  # to_be_greater_than - Edge cases
  # ==========================================================================

  def test_to_be_greater_than_with_zero
    result = Allgood::Expectation.new(1).to_be_greater_than(0)
    assert_equal true, result[:success]
  end

  def test_to_be_greater_than_with_negative_numbers
    result = Allgood::Expectation.new(-3).to_be_greater_than(-5)
    assert_equal true, result[:success]
  end

  def test_to_be_greater_than_with_floats
    result = Allgood::Expectation.new(3.15).to_be_greater_than(3.14)
    assert_equal true, result[:success]
  end

  def test_to_be_greater_than_with_very_small_difference
    result = Allgood::Expectation.new(1.0000001).to_be_greater_than(1.0)
    assert_equal true, result[:success]
  end

  def test_to_be_greater_than_with_large_numbers
    result = Allgood::Expectation.new(10**20).to_be_greater_than(10**19)
    assert_equal true, result[:success]
  end

  def test_to_be_greater_than_with_nil_raises_error
    assert_raises(NoMethodError, ArgumentError) do
      Allgood::Expectation.new(nil).to_be_greater_than(5)
    end
  end

  # ==========================================================================
  # to_be_less_than - Basic comparisons
  # ==========================================================================

  def test_to_be_less_than_when_less
    result = Allgood::Expectation.new(3).to_be_less_than(5)
    assert_equal true, result[:success]
    assert_includes result[:message], "3"
    assert_includes result[:message], "< 5"
  end

  def test_to_be_less_than_when_equal
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(5).to_be_less_than(5)
    end
    assert_includes error.message, "5"
  end

  def test_to_be_less_than_when_greater
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(10).to_be_less_than(5)
    end
    assert_includes error.message, "10"
    assert_includes error.message, "5"
  end

  # ==========================================================================
  # to_be_less_than - Edge cases
  # ==========================================================================

  def test_to_be_less_than_with_zero
    result = Allgood::Expectation.new(-1).to_be_less_than(0)
    assert_equal true, result[:success]
  end

  def test_to_be_less_than_with_negative_numbers
    result = Allgood::Expectation.new(-10).to_be_less_than(-5)
    assert_equal true, result[:success]
  end

  def test_to_be_less_than_with_floats
    result = Allgood::Expectation.new(3.13).to_be_less_than(3.14)
    assert_equal true, result[:success]
  end

  def test_to_be_less_than_with_very_small_difference
    result = Allgood::Expectation.new(0.9999999).to_be_less_than(1.0)
    assert_equal true, result[:success]
  end

  def test_to_be_less_than_with_large_numbers
    result = Allgood::Expectation.new(10**19).to_be_less_than(10**20)
    assert_equal true, result[:success]
  end

  def test_to_be_less_than_with_nil_raises_error
    assert_raises(NoMethodError, ArgumentError) do
      Allgood::Expectation.new(nil).to_be_less_than(5)
    end
  end

  # ==========================================================================
  # Message formatting validation
  # ==========================================================================

  def test_to_eq_success_message_format
    result = Allgood::Expectation.new(42).to_eq(42)
    assert_match(/Got: 42/, result[:message])
  end

  def test_to_eq_failure_message_format
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(42).to_eq(100)
    end
    assert_match(/Expected.*equal/, error.message)
  end

  def test_to_be_greater_than_success_message_format
    result = Allgood::Expectation.new(10).to_be_greater_than(5)
    assert_match(/Got: 10.*\(> 5\)/, result[:message])
  end

  def test_to_be_greater_than_failure_message_format
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(3).to_be_greater_than(5)
    end
    assert_match(/expecting.*greater than/, error.message)
  end

  def test_to_be_less_than_success_message_format
    result = Allgood::Expectation.new(3).to_be_less_than(5)
    assert_match(/Got: 3.*\(< 5\)/, result[:message])
  end

  def test_to_be_less_than_failure_message_format
    error = assert_raises(Allgood::CheckFailedError) do
      Allgood::Expectation.new(10).to_be_less_than(5)
    end
    assert_match(/expecting.*less than/, error.message)
  end
end

class CheckFailedErrorTest < Minitest::Test
  def test_check_failed_error_is_standard_error
    assert Allgood::CheckFailedError < StandardError
  end

  def test_check_failed_error_can_be_raised_with_message
    error = assert_raises(Allgood::CheckFailedError) do
      raise Allgood::CheckFailedError.new("Custom error")
    end
    assert_equal "Custom error", error.message
  end

  def test_check_failed_error_can_be_caught_as_standard_error
    caught = false
    begin
      raise Allgood::CheckFailedError.new("test")
    rescue StandardError
      caught = true
    end
    assert caught
  end
end
