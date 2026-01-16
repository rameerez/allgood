# frozen_string_literal: true

# SimpleCov configuration file (auto-loaded before test suite)
# This keeps test_helper.rb clean and follows best practices

SimpleCov.start do
  # Use SimpleFormatter for terminal-only output (no HTML generation)
  formatter SimpleCov::Formatter::SimpleFormatter

  # Track coverage for the lib directory (gem source code)
  add_filter "/test/"

  # Track the lib and app directories
  track_files "{lib,app}/**/*.rb"

  # Enable branch coverage for more detailed metrics
  enable_coverage :branch

  # Set minimum coverage threshold to prevent coverage regression
  minimum_coverage line: 80, branch: 75

  # Disambiguate parallel test runs
  command_name "Job #{ENV['TEST_ENV_NUMBER']}" if ENV['TEST_ENV_NUMBER']
end

# Print coverage summary to terminal after tests complete
SimpleCov.at_exit do
  SimpleCov.result.format!
  puts "\n" + "=" * 60
  puts "COVERAGE SUMMARY"
  puts "=" * 60
  puts "Line Coverage:   #{SimpleCov.result.covered_percent.round(2)}%"
  puts "Branch Coverage: #{SimpleCov.result.coverage_statistics[:branch]&.percent&.round(2) || 'N/A'}%"
  puts "=" * 60
end
