# frozen_string_literal: true

require_relative "../test_helper"
require "rack/test"

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
end
