# frozen_string_literal: true

require_relative "../test_helper"
require "rack/test"
require "tempfile"
require "fileutils"

# =============================================================================
# Tests covering real-world usage patterns from examples/allgood.rb
# These ensure actual production usage scenarios are battle-tested
# =============================================================================

class RealWorldThrowRaiseTest < Minitest::Test
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
  # throw vs raise behavior (from examples/allgood.rb lines 52, 58)
  # The example uses `throw` to exit early - this is Ruby's catch/throw mechanism
  # ==========================================================================

  def test_throw_inside_check_is_handled
    # Ruby's throw without a matching catch raises UncaughtThrowError
    @config.check("Throw check") do
      throw "ImageProcessing::Vips is not available"
    end

    get "/"
    assert_equal 503, last_response.status
    # The error should be caught and reported
    assert_includes last_response.body, "Error"
  end

  def test_throw_with_symbol_inside_check
    @config.check("Symbol throw") do
      throw :not_available
    end

    get "/"
    assert_equal 503, last_response.status
  end

  def test_throw_after_successful_check_still_fails
    @config.check("Conditional throw") do
      result = false
      throw "Early exit" unless result
      make_sure true
    end

    get "/"
    assert_equal 503, last_response.status
  end

  def test_throw_not_executed_when_condition_passes
    @config.check("Conditional throw - passes") do
      result = true
      throw "Should not reach" unless result
      make_sure true, "Throw was skipped"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Throw was skipped"
  end

  # ==========================================================================
  # raise vs throw - both should be handled
  # ==========================================================================

  def test_raise_string_inside_check
    @config.check("Raise string") do
      raise "Something went wrong"
    end

    get "/"
    assert_equal 503, last_response.status
    assert_includes last_response.body, "Something went wrong"
  end

  def test_raise_custom_error_class
    @config.check("Raise custom error") do
      raise ArgumentError, "Invalid argument"
    end

    get "/"
    assert_equal 503, last_response.status
    assert_includes last_response.body, "Invalid argument"
  end

  def test_raise_runtime_error
    @config.check("Raise RuntimeError") do
      raise RuntimeError, "Runtime issue"
    end

    get "/"
    assert_equal 503, last_response.status
  end
end

class RealWorldConditionalLogicTest < Minitest::Test
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
  # Complex conditional logic inside checks (from examples lines 100-104, 140-146, 160-164)
  # ==========================================================================

  def test_if_else_inside_check_block_if_branch
    @config.check("If-else check") do
      service_type = "cloud"

      if service_type != "disk"
        make_sure true, "Using cloud storage"
      else
        make_sure true, "Using disk storage"
      end
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Using cloud storage"
  end

  def test_if_else_inside_check_block_else_branch
    @config.check("If-else check") do
      service_type = "disk"

      if service_type != "disk"
        make_sure true, "Using cloud storage"
      else
        make_sure true, "Using disk storage"
      end
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Using disk storage"
  end

  def test_nested_if_conditions
    @config.check("Nested conditions") do
      all_jobs = 15
      failed_jobs = 0

      if all_jobs > 10
        percentage = (failed_jobs.to_f / all_jobs.to_f * 100)
        make_sure percentage < 1, "#{percentage.round(2)}% of jobs are failing"
      else
        make_sure true, "Not enough jobs to calculate (only #{all_jobs} jobs)"
      end
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "0.0% of jobs are failing"
  end

  def test_nested_if_conditions_else_branch
    @config.check("Nested conditions - not enough data") do
      all_jobs = 5
      failed_jobs = 1

      if all_jobs > 10
        percentage = (failed_jobs.to_f / all_jobs.to_f * 100)
        make_sure percentage < 1, "#{percentage.round(2)}% failing"
      else
        make_sure true, "Not enough jobs (only #{all_jobs})"
      end
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Not enough jobs (only 5)"
  end

  def test_in_array_check_production_style
    @config.check("Adapter check") do
      adapter = "solid_cable"
      env = "production"

      if env == "production"
        make_sure ["solid_cable", "redis"].include?(adapter), "Running #{adapter} in #{env}"
      else
        make_sure ["solid_cable", "async"].include?(adapter), "Running #{adapter} in #{env}"
      end
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Running solid_cable in production"
  end

  def test_in_array_check_fails_when_not_included
    @config.check("Adapter check - invalid") do
      adapter = "unknown"
      allowed = ["solid_cable", "redis"]

      make_sure allowed.include?(adapter), "Adapter #{adapter} must be one of #{allowed.join(', ')}"
    end

    get "/"
    assert_equal 503, last_response.status
  end

  # ==========================================================================
  # Ternary operators and compact conditionals
  # ==========================================================================

  def test_ternary_in_message
    @config.check("Ternary message") do
      value = 42
      status = value > 40 ? "high" : "low"
      make_sure true, "Value is #{status}"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Value is high"
  end

  def test_conditional_percentage_calculation
    @config.check("Percentage calculation") do
      used = 75
      total = 100
      percentage = total > 0 ? (used.to_f / total * 100).round : 0

      make_sure percentage < 90, "Usage at #{percentage}% (#{used}/#{total})"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Usage at 75%"
  end

  def test_zero_division_protection
    @config.check("Zero division safe") do
      used = 0
      total = 0
      percentage = total > 0 ? (used.to_f / total * 100).round : 0

      make_sure percentage < 90, "Usage at #{percentage}%"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Usage at 0%"
  end
end

class RealWorldShellCommandTest < Minitest::Test
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
  # Shell command execution via backticks (from examples lines 47-48, 188, 193)
  # ==========================================================================

  def test_backtick_command_execution
    @config.check("Shell command") do
      output = `echo "hello"`
      make_sure output.strip == "hello", "Echo returned: #{output.strip}"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Echo returned: hello"
  end

  def test_backtick_command_with_pipe
    @config.check("Piped command") do
      # Simulating: df -h / | tail -1 | awk '{print $5}' | sed 's/%//'
      # We'll use a simpler cross-platform example
      output = `echo "50" | cat`
      usage = output.to_i
      expect(usage).to_be_less_than(90)
    end

    get "/"
    assert last_response.ok?
  end

  def test_backtick_command_returns_empty
    @config.check("Empty command output") do
      # Using printf which is more portable than echo -n
      output = `printf ""`
      make_sure output.empty?, "Output was empty as expected"
    end

    get "/"
    assert last_response.ok?
  end

  def test_backtick_command_with_to_i_conversion
    @config.check("Command with to_i") do
      output = `echo "75"`
      usage = output.to_i
      make_sure usage == 75, "Parsed usage: #{usage}"
    end

    get "/"
    assert last_response.ok?
  end

  def test_backtick_invalid_command_handling
    @config.check("Invalid command") do
      # This command doesn't exist but shouldn't crash Ruby
      output = `nonexistent_command_12345 2>/dev/null`
      # Just verify we can handle the empty/error output
      make_sure true, "Handled gracefully"
    end

    get "/"
    # Should still work, just with empty output
    assert last_response.ok?
  end

  def test_present_check_on_command_output
    @config.check("Present check on output") do
      output = `echo "some output"`
      # Simulating: output.present? && output.include?("something")
      has_content = !output.nil? && !output.empty?
      includes_output = output.include?("some")

      make_sure has_content && includes_output, "Output present and contains expected text"
    end

    get "/"
    assert last_response.ok?
  end
end

class RealWorldBeginRescueTest < Minitest::Test
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
  # begin/rescue/end error handling (from examples lines 170-182)
  # ==========================================================================

  def test_begin_rescue_catches_error
    @config.check("Rescued check") do
      begin
        raise "Simulated failure"
        make_sure true
      rescue => e
        make_sure false, "Failed: #{e.message}"
      end
    end

    get "/"
    assert_equal 503, last_response.status
    assert_includes last_response.body, "Failed: Simulated failure"
  end

  def test_begin_rescue_success_path
    @config.check("Successful rescued check") do
      begin
        result = "success"
        make_sure result == "success", "Operation succeeded"
      rescue => e
        make_sure false, "Failed: #{e.message}"
      end
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Operation succeeded"
  end

  def test_begin_rescue_with_multiple_operations
    @config.check("Multi-step operation") do
      begin
        # Step 1: Create
        created = true
        # Step 2: Verify
        verified = true
        # Step 3: Cleanup
        cleaned_up = true

        make_sure created && verified && cleaned_up, "All steps completed"
      rescue => e
        make_sure false, "Failed at step: #{e.message}"
      end
    end

    get "/"
    assert last_response.ok?
  end

  def test_begin_rescue_specific_error_type
    @config.check("Specific error rescue") do
      begin
        raise ArgumentError, "Bad arg"
      rescue ArgumentError => e
        make_sure false, "ArgumentError: #{e.message}"
      rescue StandardError => e
        make_sure false, "Other error: #{e.message}"
      end
    end

    get "/"
    assert_equal 503, last_response.status
    assert_includes last_response.body, "ArgumentError: Bad arg"
  end

  def test_ensure_block_runs
    @config.check("With ensure") do
      cleanup_ran = false
      begin
        # Simulating work
        result = true
      ensure
        cleanup_ran = true
      end

      make_sure result && cleanup_ran, "Operation completed with cleanup"
    end

    get "/"
    assert last_response.ok?
  end
end

class RealWorldVariableAssignmentTest < Minitest::Test
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
  # Variable assignment and reuse (from examples lines 15-27, 30-37, 98-99, etc.)
  # ==========================================================================

  def test_multiple_variable_assignments
    @config.check("Multiple variables") do
      table_name = "test_table_#{Time.now.to_i}"
      random_id = rand(1..999999)

      # Simulate using these variables
      result = { table: table_name, id: random_id }

      make_sure result[:table].start_with?("test_table_") && result[:id].positive?,
                "Created #{result[:table]} with ID #{result[:id]}"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "test_table_"
  end

  def test_calculated_values_with_formatting
    @config.check("Formatted calculations") do
      used_connections = 7
      max_connections = 10
      usage_percentage = (used_connections.to_f / max_connections * 100).round

      make_sure usage_percentage < 90, "Pool usage at #{usage_percentage}% (#{used_connections}/#{max_connections})"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Pool usage at 70% (7/10)"
  end

  def test_chained_method_calls_on_result
    @config.check("Method chaining") do
      # Simulating: service&.class&.name&.split("::")&.last&.split("Service")&.first
      full_name = "ActiveStorage::Service::DiskService"
      service_name = full_name.split("::").last.split("Service").first

      make_sure service_name == "Disk", "Service is #{service_name}"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Service is Disk"
  end

  def test_safe_navigation_simulation
    @config.check("Safe navigation") do
      # Simulating safe navigation with nil checks
      service = { class_name: "DiskService" }

      service_name = service && service[:class_name] ? service[:class_name].gsub("Service", "") : nil

      make_sure service_name == "Disk", "Found service: #{service_name || 'unknown'}"
    end

    get "/"
    assert last_response.ok?
  end

  def test_nil_safe_navigation_with_nil_value
    @config.check("Nil-safe navigation") do
      service = nil

      service_name = service && service[:class_name] ? service[:class_name] : "unknown"

      make_sure service_name == "unknown", "Service: #{service_name}"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Service: unknown"
  end
end

class RealWorldFileOperationsTest < Minitest::Test
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
  # File existence checks (from examples lines 203-204)
  # ==========================================================================

  def test_file_exist_check_when_exists
    # Create a temp file
    tempfile = Tempfile.new(['allgood_test', '.txt'])
    tempfile.write("test content")
    tempfile.close

    @config.check("File exists") do
      make_sure File.exist?(tempfile.path), "File found at #{tempfile.path}"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "File found at"
  ensure
    tempfile.unlink if tempfile
  end

  def test_file_exist_check_when_not_exists
    @config.check("File missing") do
      path = "/nonexistent/path/file_#{Time.now.to_i}.txt"
      make_sure File.exist?(path), "File should exist at #{path}"
    end

    get "/"
    assert_equal 503, last_response.status
  end

  def test_directory_exist_check
    @config.check("Directory exists") do
      make_sure Dir.exist?("/tmp"), "Temp directory exists"
    end

    get "/"
    assert last_response.ok?
  end

  def test_file_readable_check
    tempfile = Tempfile.new(['readable_test', '.txt'])
    tempfile.write("readable content")
    tempfile.close

    @config.check("File readable") do
      make_sure File.readable?(tempfile.path), "File is readable"
    end

    get "/"
    assert last_response.ok?
  ensure
    tempfile.unlink if tempfile
  end
end

class RealWorldTimeRangeTest < Minitest::Test
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
  # Time range queries (from examples lines 138-139, 210-211)
  # Simulating: .where(created_at: 24.hours.ago..Time.now)
  # ==========================================================================

  def test_time_range_check
    @config.check("Time range check") do
      # Simulate a time range query result
      records_in_range = [
        { created_at: Time.now - 1.hour },
        { created_at: Time.now - 12.hours }
      ]

      make_sure records_in_range.any?, "Found #{records_in_range.count} records in last 24h"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Found 2 records"
  end

  def test_time_range_empty_result
    @config.check("Empty time range") do
      records_in_range = []

      if records_in_range.any?
        make_sure true, "Found records"
      else
        make_sure false, "No records found in the last 24 hours"
      end
    end

    get "/"
    assert_equal 503, last_response.status
    assert_includes last_response.body, "No records found"
  end

  def test_time_formatting_in_message
    travel_to Time.utc(2024, 6, 15, 14, 30, 0) do
      @config.check("Time formatted") do
        timestamp = Time.current
        make_sure true, "Check run at #{timestamp.strftime('%Y-%m-%d %H:%M:%S %Z')}"
      end

      get "/"
      assert last_response.ok?
      assert_includes last_response.body, "2024-06-15"
    end
  end

  def test_dynamic_timestamp_in_key
    @config.check("Dynamic key") do
      cache_key = "allgood_test_#{Time.now.to_i}"
      make_sure cache_key.match?(/allgood_test_\d+/), "Key: #{cache_key}"
    end

    get "/"
    assert last_response.ok?
  end
end

class RealWorldCleanupPatternTest < Minitest::Test
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
  # Create/verify/cleanup patterns (from examples lines 107-113, 167-183)
  # ==========================================================================

  def test_create_verify_cleanup_pattern
    @config.check("Create-verify-cleanup") do
      # Create
      resource = { id: rand(1000), created: true }

      # Verify
      verified = resource[:created] == true

      # Cleanup
      resource = nil
      cleaned_up = resource.nil?

      make_sure verified && cleaned_up, "Resource lifecycle completed"
    end

    get "/"
    assert last_response.ok?
  end

  def test_create_verify_cleanup_with_failure_at_verify
    @config.check("Cleanup on verify failure") do
      # Create
      resource = { id: rand(1000), data: nil }

      # Verify fails
      verified = !resource[:data].nil?

      # Cleanup should still happen
      resource = nil

      make_sure verified, "Resource verification failed"
    end

    get "/"
    assert_equal 503, last_response.status
  end

  def test_write_read_delete_cache_pattern
    @config.check("Cache write-read-delete") do
      cache_key = "allgood_test_#{Time.now.to_i}"
      cache_value = "test_value"

      # Simulate cache operations
      cache = { cache_key => cache_value }

      # Write
      written = cache[cache_key] == cache_value

      # Read
      read_value = cache[cache_key]
      read_correct = read_value == cache_value

      # Delete
      cache.delete(cache_key)
      deleted = cache[cache_key].nil?

      make_sure written && read_correct && deleted, "Cache operations successful"
    end

    get "/"
    assert last_response.ok?
  end
end

class RealWorldStringInterpolationTest < Minitest::Test
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
  # Complex string interpolation (from examples throughout)
  # ==========================================================================

  def test_multiple_interpolations_in_message
    @config.check("Multi-interpolation") do
      used = 7
      max = 10
      percentage = 70

      make_sure true, "Pool usage at #{percentage}% (#{used}/#{max})"
    end

    get "/"
    assert_includes last_response.body, "Pool usage at 70% (7/10)"
  end

  def test_method_call_in_interpolation
    @config.check("Method in interpolation") do
      value = 3.14159
      make_sure true, "Pi rounded: #{value.round(2)}"
    end

    get "/"
    assert_includes last_response.body, "Pi rounded: 3.14"
  end

  def test_conditional_in_interpolation
    @config.check("Conditional interpolation") do
      count = 0
      make_sure true, "Found #{count > 0 ? count : 'no'} records"
    end

    get "/"
    assert_includes last_response.body, "Found no records"
  end

  def test_array_join_in_interpolation
    @config.check("Array join") do
      adapters = ["redis", "solid_cable"]
      make_sure true, "Supported: #{adapters.join(', ')}"
    end

    get "/"
    assert_includes last_response.body, "Supported: redis, solid_cable"
  end

  def test_nested_object_access_in_interpolation
    @config.check("Nested access") do
      config = { storage: { service: { name: "S3" } } }
      make_sure true, "Using #{config[:storage][:service][:name]} storage"
    end

    get "/"
    assert_includes last_response.body, "Using S3 storage"
  end
end

class RealWorldCompoundConditionsTest < Minitest::Test
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
  # Compound && and || conditions (from examples lines 47-48, 68, 93, etc.)
  # ==========================================================================

  def test_and_conditions_all_true
    @config.check("AND all true") do
      a = true
      b = true
      c = true
      make_sure a && b && c, "All conditions met"
    end

    get "/"
    assert last_response.ok?
  end

  def test_and_conditions_one_false
    @config.check("AND one false") do
      a = true
      b = false
      c = true
      make_sure a && b && c, "All conditions should be met"
    end

    get "/"
    assert_equal 503, last_response.status
  end

  def test_or_conditions
    @config.check("OR conditions") do
      a = false
      b = true
      make_sure a || b, "At least one condition met"
    end

    get "/"
    assert last_response.ok?
  end

  def test_mixed_and_or_conditions
    @config.check("Mixed AND/OR") do
      # Simulating: output.present? && output.include?("libvips.so") && output.include?("libvips-cpp.so")
      output = "libvips.so.42 libvips-cpp.so.42"
      has_content = !output.nil? && !output.empty?
      has_libvips = output.include?("libvips.so")
      has_cpp = output.include?("libvips-cpp.so")

      make_sure has_content && has_libvips && has_cpp, "Found required libraries"
    end

    get "/"
    assert last_response.ok?
  end

  def test_negation_conditions
    @config.check("Negation") do
      production = false
      make_sure !production, "Not in production"
    end

    get "/"
    assert last_response.ok?
  end

  def test_comparison_chain
    @config.check("Comparison chain") do
      width = 268
      height = 177
      expected_width = 268
      expected_height = 177

      make_sure width == expected_width && height == expected_height,
                "Dimensions: #{width}x#{height}"
    end

    get "/"
    assert last_response.ok?
  end

  def test_nil_check_with_and
    @config.check("Nil with AND") do
      result = { data: "value" }
      make_sure !result.nil? && result[:data] == "value", "Result valid"
    end

    get "/"
    assert last_response.ok?
  end

  def test_nil_check_short_circuit
    @config.check("Short circuit on nil") do
      result = nil
      # Short-circuit evaluation prevents NoMethodError
      valid = result && result[:data] == "value"
      make_sure !valid, "Result was nil (expected)"
    end

    get "/"
    assert last_response.ok?
  end
end

class RealWorldMethodResponseTest < Minitest::Test
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
  # Checking method responses (from examples lines 51, 89, 101, 125, etc.)
  # Simulating: .present?, .respond_to?, .any?, etc.
  # ==========================================================================

  def test_present_check_on_string
    @config.check("Present string") do
      value = "hello"
      is_present = !value.nil? && !value.empty?
      make_sure is_present, "Value is present"
    end

    get "/"
    assert last_response.ok?
  end

  def test_present_check_on_empty_string
    @config.check("Empty string not present") do
      value = ""
      is_present = !value.nil? && !value.empty?
      make_sure !is_present, "Empty string is not present"
    end

    get "/"
    assert last_response.ok?
  end

  def test_present_check_on_nil
    @config.check("Nil not present") do
      value = nil
      is_present = !value.nil?
      make_sure !is_present, "Nil is not present"
    end

    get "/"
    assert last_response.ok?
  end

  def test_respond_to_check
    @config.check("Respond to check") do
      obj = "string"
      make_sure obj.respond_to?(:upcase), "Object responds to upcase"
    end

    get "/"
    assert last_response.ok?
  end

  def test_respond_to_missing_method
    @config.check("Missing method") do
      obj = "string"
      make_sure !obj.respond_to?(:nonexistent_method), "Object doesn't respond to nonexistent"
    end

    get "/"
    assert last_response.ok?
  end

  def test_any_check_on_array
    @config.check("Any check") do
      items = [1, 2, 3]
      make_sure items.any?, "Array has items"
    end

    get "/"
    assert last_response.ok?
  end

  def test_any_check_on_empty_array
    @config.check("Empty array any") do
      items = []
      make_sure items.any?, "Array should have items"
    end

    get "/"
    assert_equal 503, last_response.status
  end

  def test_positive_check
    @config.check("Positive check") do
      count = 5
      make_sure count.positive?, "Count is positive"
    end

    get "/"
    assert last_response.ok?
  end

  def test_zero_not_positive
    @config.check("Zero not positive") do
      count = 0
      make_sure count.positive?, "Count should be positive"
    end

    get "/"
    assert_equal 503, last_response.status
  end
end

class RealWorldDatabasePatternTest < Minitest::Test
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
  # Database-style patterns (simulated, from examples lines 6-42)
  # ==========================================================================

  def test_connection_active_check_simulation
    @config.check("Connection active") do
      connection = { active: true }
      make_sure connection[:active], "Database connection is active"
    end

    get "/"
    assert last_response.ok?
  end

  def test_table_exists_check_simulation
    @config.check("Tables exist") do
      tables = ["users", "posts", "comments"]
      make_sure tables.include?("users") && tables.include?("posts"),
                "Required tables exist"
    end

    get "/"
    assert last_response.ok?
  end

  def test_query_result_check
    @config.check("Query result") do
      result = [{ "id" => 1 }]
      make_sure result.any?, "Query returned results"
    end

    get "/"
    assert last_response.ok?
  end

  def test_specific_value_in_result
    @config.check("Specific value check") do
      result = [{ "id" => 12345 }]
      expected_id = 12345

      make_sure result.any? && result.first["id"] == expected_id,
                "Found expected ID: #{expected_id}"
    end

    get "/"
    assert last_response.ok?
  end

  def test_pool_health_check_simulation
    @config.check("Pool health") do
      pool = {
        connections: 3,
        size: 10
      }

      usage = (pool[:connections].to_f / pool[:size] * 100).round
      make_sure usage < 90, "Pool at #{usage}%"
    end

    get "/"
    assert last_response.ok?
    assert_includes last_response.body, "Pool at 30%"
  end

  def test_migrations_pending_check_simulation
    @config.check("Migrations check") do
      # Simulating ActiveRecord::Migration.check_all_pending! which returns nil if OK
      check_result = nil
      make_sure check_result.nil?, "No pending migrations"
    end

    get "/"
    assert last_response.ok?
  end
end
