# frozen_string_literal: true

require_relative "../test_helper"
require "rack/test"

class EngineTest < Minitest::Test
  include Rack::Test::Methods

  def app
    TEST_ROUTER
  end

  def test_engine_inherits_from_rails_engine
    assert Allgood::Engine < Rails::Engine
  end

  def test_engine_routes_root
    get "/"
    refute_equal 404, last_response.status
  end
end