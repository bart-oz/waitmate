# frozen_string_literal: true

class WaitmateTestController < ApplicationController
  include Waitmate::ControllerConcern

  wait_room :index, max_concurrent: 2

  def index
    render plain: "admitted"
  end

  def public
    render plain: "public"
  end
end
