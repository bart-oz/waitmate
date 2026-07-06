# frozen_string_literal: true

require "active_support"
require "active_support/concern"

module Waitmate
  # Shared validation for the relative target URL that is threaded between the
  # host controller and the Engine waiting room. Keeping this in one place
  # ensures the concern-emit path and the room-redirect path never diverge.
  module TargetValidation
    extend ActiveSupport::Concern

    included { private }

    def valid_waiting_room_target?(target)
      return false unless target.is_a?(String) && target.start_with?("/")
      return false if target.start_with?("//")
      return false if target.include?("://")
      return false if target.match?(/\Ajavascript:/i)
      true
    end
  end

  # Provides the +wait_room+ controller macro. Host controllers include this
  # concern and declare which actions are capacity-gated:
  #
  #   class CheckoutsController < ApplicationController
  #     include Waitmate::ControllerConcern
  #     wait_room :create, max_concurrent: 500
  #   end
  #
  # The macro is transport-agnostic: it performs capacity-check → redirect →
  # return-verify without knowing whether the waiting room uses polling,
  # ActionCable, or full-page reloads.
  module ControllerConcern
    extend ActiveSupport::Concern
    include TargetValidation

    class_methods do
      def wait_room(action, max_concurrent:)
        before_action(only: action) { handle_wait_room(max_concurrent: max_concurrent) }
      end
    end

    private

    def handle_wait_room(max_concurrent:)
      queue_name = action_name.to_s
      session_id = session.id.to_s

      if params[:ticket].present?
        handle_return(queue_name, session_id, max_concurrent)
      else
        handle_initial(queue_name, session_id, max_concurrent)
      end
    end

    def handle_initial(queue_name, session_id, max_concurrent)
      Store.enqueue(queue_name, session_id)
      Store.admit(queue_name, max_concurrent, count: 1)

      return if Store.position(queue_name, session_id) == 0

      redirect_to_waiting_room(
        ticket: Ticket.issue(queue_name: queue_name, session_id: session_id),
        queue: queue_name,
        target: request.fullpath
      )
    end

    def handle_return(queue_name, session_id, max_concurrent)
      result = Ticket.verify(token: params[:ticket], queue_name: queue_name, session_id: session_id)
      target = request.fullpath
      return redirect_to_waiting_room(queue: queue_name, target: target) unless result.success?

      Store.admit(queue_name, max_concurrent, count: 1)

      return if Store.position(queue_name, session_id) == 0

      redirect_to_waiting_room(ticket: params[:ticket], queue: queue_name, target: target)
    end

    def redirect_to_waiting_room(ticket: nil, queue: nil, target: nil)
      path = Waitmate.configuration.waiting_room_path
      query = {ticket: ticket, queue: queue}.compact
      query[:target] = target if valid_waiting_room_target?(target)
      path += "?#{query.to_query}" if query.any?
      redirect_to(path)
    end
  end
end
