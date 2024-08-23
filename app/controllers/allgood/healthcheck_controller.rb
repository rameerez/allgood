require 'timeout'

module Allgood
  class HealthcheckController < ApplicationController
    def index
      @results = run_checks
      @status = @results.all? { |r| r[:success] } ? "ok" : "error"

      respond_to do |format|
        format.html
        format.json { render json: { status: @status, checks: @results } }
      end
    rescue StandardError => e
      # Log the error
      Rails.logger.error "Allgood Healthcheck Error: #{e.message}\n#{e.backtrace.join("\n")}"

      # Return a minimal response
      @results = [{ name: "Healthcheck Error", success: false, message: "Internal error occurred", duration: 0 }]
      @status = "error"

      respond_to do |format|
        format.html { render :index, status: :internal_server_error }
        format.json { render json: { status: @status, checks: @results }, status: :internal_server_error }
      end
    end

    private

    def run_checks
      Allgood.configuration.checks.map do |check|
        run_single_check(check)
      end
    end

    def run_single_check(check)
      start_time = Time.now
      result = { success: false, message: "Check timed out after #{check[:timeout]} seconds" }

      begin
        Timeout.timeout(check[:timeout]) do
          success = Allgood.configuration.run_check(&check[:block])
          result = { success: success, message: success ? "Check passed" : "Check failed" }
        end
      rescue Timeout::Error
        # The result is already set to a timeout message
      rescue Allgood::CheckFailedError => e
        result = { success: false, message: e.message }
      rescue StandardError => e
        result = { success: false, message: "Error: #{e.message}" }
      end

      {
        name: check[:name],
        success: result[:success],
        message: result[:message],
        duration: ((Time.now - start_time) * 1000).round(1)
      }
    end
  end
end
