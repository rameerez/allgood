module Allgood
  class HealthcheckController < ApplicationController
    def index
      @results = run_checks
      @status = @results.all? { |r| r[:success] } ? "ok" : "error"

      respond_to do |format|
        format.html
        format.json { render json: { status: @status, checks: @results } }
      end
    end

    private

    def run_checks
      Allgood.configuration.checks.map do |check|
        start_time = Time.now
        result = instance_eval(&check[:block])
        end_time = Time.now
        duration = ((end_time - start_time) * 1000).round(1)

        {
          name: check[:name],
          success: result[:success],
          message: result[:message],
          duration: duration
        }
      end
    end
  end
end
