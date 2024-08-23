module Allgood
  class HealthcheckController < ApplicationController
    def index
      @status = "ok"

      respond_to do |format|
        format.html
        format.json { render json: { status: @status } }
      end
    end
  end
end
