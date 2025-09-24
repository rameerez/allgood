require 'timeout'

module Allgood
  class HealthcheckController < BaseController
    def index
      @results = run_checks
      @status = @results.all? { |r| r[:success] } ? "ok" : "error"
      status_code = @status == "ok" ? :ok : :service_unavailable

      respond_to do |format|
        format.html { render :index, status: status_code }
        format.json { render json: { status: @status, checks: @results }, status: status_code }
      end
    rescue StandardError => e
      # Log the error
      Rails.logger.error "Allgood Healthcheck Error: #{e.message}\n#{e.backtrace.join("\n")}"

      # Return a minimal response
      @results = [ { name: "Healthcheck Error", success: false, message: "Internal error occurred", duration: 0 } ]
      @status = "error"

      respond_to do |format|
        format.html { render :index, status: :internal_server_error }
        format.json { render json: { status: @status, checks: @results }, status: :internal_server_error }
      end
    end

    private

    def run_checks
      Allgood.configuration.checks.map do |check|
        if check[:status] == :skipped
          {
            name: check[:name],
            description: check[:description],
            success: true,
            skipped: true,
            message: check[:skip_reason],
            duration: 0
          }
        else
          run_single_check(check)
        end
      end
    end

    def run_single_check(check)
      last_result_key = "allgood:last_result:#{check[:name].parameterize}"
      last_result = Allgood::CacheStore.instance.read(last_result_key)

      unless Allgood.configuration.should_run_check?(check)
        message = check[:skip_reason]
        if last_result
          status_info = "Last check #{last_result[:success] ? 'passed' : 'failed'} #{time_ago_in_words(last_result[:time])} ago: #{last_result[:message]}"
          message = "#{message}. #{status_info}"
        end

        return {
          name: check[:name],
          description: check[:description],
          success: last_result ? last_result[:success] : true,
          skipped: true,
          message: message,
          duration: 0
        }
      end

      start_time = Time.now
      result = {
        description: check[:description],
        success: false,
        message: "Check timed out after #{check[:timeout]} seconds"
      }
      error_key = "allgood:error:#{check[:name].parameterize}"

      begin
        Timeout.timeout(check[:timeout]) do
          check_result = Allgood.configuration.run_check(&check[:block])
          result = { success: check_result[:success], message: check_result[:message] }

          if result[:success]
            # Clear error state and store successful result
            Allgood::CacheStore.instance.write(error_key, nil)
            Allgood::CacheStore.instance.write(last_result_key, {
              success: true,
              message: result[:message],
              time: Time.current
            })
          end
        end
      rescue Timeout::Error, Allgood::CheckFailedError, StandardError => e
        error_message = case e
        when Timeout::Error
          "Check timed out after #{check[:timeout]} seconds"
        when Allgood::CheckFailedError
          e.message
        else
          "Error: #{e.message}"
        end

        # Store error state and failed result
        Allgood::CacheStore.instance.write(error_key, error_message)
        Allgood::CacheStore.instance.write(last_result_key, {
          success: false,
          message: error_message,
          time: Time.current
        })
        result = { success: false, message: error_message }
      end

      {
        name: check[:name],
        description: check[:description],
        success: result[:success],
        message: result[:message],
        duration: ((Time.now - start_time) * 1000).round(1)
      }
    end
  end
end
