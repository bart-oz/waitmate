# frozen_string_literal: true

module Waitmate
  class RoomsController < ApplicationController
    include TargetValidation

    before_action :verify_ticket, only: [:show]

    def show
      pos = current_position
      return render_invalid if pos.nil?

      if pos == 0
        url = admission_url
        return redirect_to(url) if url
        return render_invalid
      end

      @position = pos
      @polling_interval = Waitmate.configuration.polling_interval
      @ticket = ticket_param
      @queue = queue_param
      @target = validated_target
    end

    def position
      result = Ticket.verify(token: ticket_param, queue_name: queue_param, session_id: session.id.to_s)
      return render_position_json(position: nil, admitted: false) unless result.success?

      Store.heartbeat(queue_param, session.id.to_s)
      pos = Store.position(queue_param, session.id.to_s)

      render_position_json(position: pos, admitted: pos == 0)
    end

    private

    def verify_ticket
      result = Ticket.verify(token: ticket_param, queue_name: queue_param, session_id: session.id.to_s)
      return render_invalid unless result.success?

      Store.heartbeat(queue_param, session.id.to_s)
    end

    def current_position
      Store.position(queue_param, session.id.to_s)
    end

    def render_invalid
      @error = true
      @position = nil
      @polling_interval = Waitmate.configuration.polling_interval
      render "waitmate/rooms/show", status: :ok
    end

    def render_position_json(position:, admitted:)
      render json: {
        position: position,
        admitted: admitted,
        retry: Waitmate.configuration.polling_interval
      }, status: :ok, headers: private_cache_headers
    end

    def admission_url
      target = validated_target
      return nil unless target

      separator = target.include?("?") ? "&" : "?"
      query = {ticket: ticket_param}.to_query
      "#{target}#{separator}#{query}"
    end

    def ticket_param
      params[:ticket].to_s
    end

    def queue_param
      params[:queue].to_s
    end

    def target_param
      params[:target].to_s
    end

    def validated_target
      @validated_target ||= target_param if valid_waiting_room_target?(target_param)
    end

    def private_cache_headers
      interval = Waitmate.configuration.polling_interval
      {
        "Cache-Control" => "private, max-age=#{[interval - 1, 0].max}",
        "Pragma" => "no-cache"
      }
    end
  end
end
