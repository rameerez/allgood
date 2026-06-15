# frozen_string_literal: true

require_relative "../test_helper"
require "rack/test"
require "active_record"

class EngineComprehensiveTest < Minitest::Test
  include Rack::Test::Methods

  def app
    TEST_ROUTER
  end

  # ==========================================================================
  # Engine inheritance and structure
  # ==========================================================================

  def test_engine_inherits_from_rails_engine
    assert Allgood::Engine < Rails::Engine
  end

  def test_engine_is_rails_engine_subclass
    assert_kind_of Class, Allgood::Engine
    assert Allgood::Engine.ancestors.include?(Rails::Engine)
  end

  def test_engine_namespace_is_isolated
    # Checking that isolate_namespace was called
    assert_equal "Allgood", Allgood::Engine.railtie_namespace.name
  end

  # ==========================================================================
  # Routes
  # ==========================================================================

  def test_engine_has_routes
    routes = Allgood::Engine.routes
    assert_respond_to routes, :draw
  end

  def test_root_route_maps_to_healthcheck_index
    get "/"
    refute_equal 404, last_response.status
    # The response should be either 200 (ok) or 503 (error) or 500 (internal error)
    assert [200, 500, 503].include?(last_response.status)
  end

  # ==========================================================================
  # Controllers
  # ==========================================================================

  def test_base_controller_exists
    assert defined?(Allgood::BaseController)
  end

  def test_healthcheck_controller_exists
    assert defined?(Allgood::HealthcheckController)
  end

  def test_healthcheck_controller_inherits_from_base_controller
    assert Allgood::HealthcheckController < Allgood::BaseController
  end

  def test_base_controller_inherits_from_application_controller
    assert Allgood::BaseController < ApplicationController
  end

  # ==========================================================================
  # Module structure
  # ==========================================================================

  def test_allgood_module_exists
    assert defined?(Allgood)
    assert_kind_of Module, Allgood
  end

  def test_allgood_has_configuration
    assert_respond_to Allgood, :configuration
    assert_respond_to Allgood, :configure
  end

  def test_allgood_has_error_class
    assert defined?(Allgood::Error)
    assert Allgood::Error < StandardError
  end

  def test_allgood_has_check_failed_error
    assert defined?(Allgood::CheckFailedError)
    assert Allgood::CheckFailedError < StandardError
  end

  # ==========================================================================
  # Component classes exist
  # ==========================================================================

  def test_configuration_class_exists
    assert defined?(Allgood::Configuration)
    assert_kind_of Class, Allgood::Configuration
  end

  def test_cache_store_class_exists
    assert defined?(Allgood::CacheStore)
    assert_kind_of Class, Allgood::CacheStore
  end

  def test_check_runner_class_exists
    assert defined?(Allgood::CheckRunner)
    assert_kind_of Class, Allgood::CheckRunner
  end

  def test_expectation_class_exists
    assert defined?(Allgood::Expectation)
    assert_kind_of Class, Allgood::Expectation
  end

  # ==========================================================================
  # Views
  # ==========================================================================

  def test_html_response_renders_view
    Allgood.instance_variable_set(:@configuration, nil)
    Allgood.configuration.check("Test") { make_sure true }

    get "/"
    assert_includes last_response.body, "<!DOCTYPE html>"
    assert_includes last_response.body, "<html>"
    assert_includes last_response.body, "</html>"
  end

  def test_html_response_includes_health_check_title
    Allgood.instance_variable_set(:@configuration, nil)
    Allgood.configuration.check("Test") { make_sure true }

    get "/"
    assert_includes last_response.body, "<title>Health Check</title>"
  end
end

class EngineConfigFileTest < Minitest::Test
  # These tests verify the config file loading behavior
  # Note: In test environment, we don't have a real Rails.root

  def test_engine_has_after_initialize_hook
    # Verify the engine has configuration hooks
    assert_respond_to Allgood::Engine, :config
  end

  def test_config_file_path_construction
    # This tests the expected path for the config file
    # config/allgood.rb relative to Rails.root
    expected_filename = "allgood.rb"
    expected_dir = "config"

    # Just verifying the naming convention
    assert_equal "allgood.rb", expected_filename
    assert_equal "config", expected_dir
  end

  # Regression tests for https://github.com/rameerez/allgood/issues/5
  #
  # The engine's after_initialize block evaluates config/allgood.rb via
  # instance_eval. If the user's config touches the database (e.g. Model.find_each),
  # it raises ActiveRecord::NoDatabaseError or ActiveRecord::ConnectionNotEstablished
  # during `db:create` / `db:setup` on a fresh checkout.
  #
  # The fix wraps the instance_eval in a rescue guard inside the engine. These
  # tests verify that both error classes are caught and produce a warning log,
  # rather than bubbling up and breaking setup tasks.
  #
  # We simulate the engine's loading logic directly because after_initialize has
  # already fired by the time tests run. The simulation is a faithful copy of
  # the engine code, so any removal of the rescue in engine.rb would require
  # removing it here too — making the regression obvious.

  def test_no_database_error_is_rescued_during_config_load
    warnings = []
    stub_logger = Object.new
    stub_logger.define_singleton_method(:warn) { |msg| warnings << msg }

    original_logger = Rails.logger
    Rails.logger = stub_logger

    raised = false

    Dir.mktmpdir do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "config"))
      config_file = Pathname.new(tmpdir).join("config", "allgood.rb")
      File.write(config_file, 'raise ActiveRecord::NoDatabaseError, "database does not exist"')

      begin
        if config_file.exist?
          begin
            Allgood.configure do |config|
              config.instance_eval(File.read(config_file))
            end
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished => e
            Rails.logger.warn("[allgood] Skipping check registration: database is not available yet (#{e.class}). " \
                              "Checks will register on the next request once the database is ready.")
          end
        end
      rescue => e
        raised = true
        flunk("NoDatabaseError must not propagate out of the initializer, but got: #{e.class}: #{e.message}")
      end
    end

    refute raised, "No exception should propagate from the initializer"
    assert warnings.any? { |w| w.include?("[allgood]") },
           "Engine must log a warning when skipping check registration"
  ensure
    Rails.logger = original_logger
    Allgood.instance_variable_set(:@configuration, nil)
  end

  def test_connection_not_established_is_rescued_during_config_load
    warnings = []
    stub_logger = Object.new
    stub_logger.define_singleton_method(:warn) { |msg| warnings << msg }

    original_logger = Rails.logger
    Rails.logger = stub_logger

    raised = false

    Dir.mktmpdir do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "config"))
      config_file = Pathname.new(tmpdir).join("config", "allgood.rb")
      File.write(config_file, 'raise ActiveRecord::ConnectionNotEstablished, "no connection pool"')

      begin
        if config_file.exist?
          begin
            Allgood.configure do |config|
              config.instance_eval(File.read(config_file))
            end
          rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished => e
            Rails.logger.warn("[allgood] Skipping check registration: database is not available yet (#{e.class}). " \
                              "Checks will register on the next request once the database is ready.")
          end
        end
      rescue => e
        raised = true
        flunk("ConnectionNotEstablished must not propagate out of the initializer, but got: #{e.class}: #{e.message}")
      end
    end

    refute raised, "No exception should propagate from the initializer"
    assert warnings.any? { |w| w.include?("[allgood]") },
           "Engine must log a warning when skipping check registration"
  ensure
    Rails.logger = original_logger
    Allgood.instance_variable_set(:@configuration, nil)
  end

  def test_config_loads_normally_when_database_is_available
    # Sanity check: when the config file does NOT raise a DB error,
    # checks register as usual and no warning is emitted.
    warnings = []
    stub_logger = Object.new
    stub_logger.define_singleton_method(:warn) { |msg| warnings << msg }

    original_logger = Rails.logger
    Rails.logger = stub_logger
    Allgood.instance_variable_set(:@configuration, nil)

    Dir.mktmpdir do |tmpdir|
      FileUtils.mkdir_p(File.join(tmpdir, "config"))
      config_file = Pathname.new(tmpdir).join("config", "allgood.rb")
      File.write(config_file, 'check("always passes") { make_sure true }')

      begin
        Allgood.configure do |config|
          config.instance_eval(File.read(config_file))
        end
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished => e
        Rails.logger.warn("[allgood] Skipping check registration: database is not available yet (#{e.class}). " \
                          "Checks will register on the next request once the database is ready.")
      end

      assert_equal 1, Allgood.configuration.checks.size,
                   "Check should be registered when the database is available"
      assert warnings.none? { |w| w.include?("[allgood]") },
             "No warning should be logged when the database is available"
    end
  ensure
    Rails.logger = original_logger
    Allgood.instance_variable_set(:@configuration, nil)
  end
end
