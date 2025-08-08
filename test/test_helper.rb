# frozen_string_literal: true

require "minitest/autorun"
require "rack/test"
require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "active_support/testing/time_helpers"
require "fileutils"
require "json"
require "logger"
require "nokogiri"

# Define host app ApplicationController for engine to inherit from
class ApplicationController < ActionController::Base
  include ActionView::Helpers::DateHelper
end

require "allgood"

# Load engine controllers
require File.expand_path("../app/controllers/allgood/base_controller", __dir__)
require File.expand_path("../app/controllers/allgood/healthcheck_controller", __dir__)

Rails.env = ActiveSupport::StringInquirer.new("test")
Rails.logger = Logger.new($stdout)

# Ensure controller can find engine view templates
Allgood::HealthcheckController.append_view_path(File.expand_path("../app/views", __dir__))

# Minimal router for controller integration tests (bypasses engine mounting)
TEST_ROUTER = ActionDispatch::Routing::RouteSet.new
TEST_ROUTER.draw do
  scope module: "allgood" do
    get "/" => "healthcheck#index"
  end
end

# Configure controller to use the test router helpers
Allgood::HealthcheckController.include TEST_ROUTER.url_helpers

module Minitest
  class Test
    include ActiveSupport::Testing::TimeHelpers
  end
end