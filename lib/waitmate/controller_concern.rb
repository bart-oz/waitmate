# frozen_string_literal: true

require "active_support"
require "active_support/concern"

module Waitmate
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
        ticket: Ticket.issue(queue_name: queue_name, session_id: session_id)
      )
    end

    def handle_return(queue_name, session_id, max_concurrent)
      result = Ticket.verify(token: params[:ticket], queue_name: queue_name, session_id: session_id)
      return redirect_to_waiting_room unless result.success?

      Store.admit(queue_name, max_concurrent, count: 1)

      return if Store.position(queue_name, session_id) == 0

      redirect_to_waiting_room
    end

    def redirect_to_waiting_room(ticket: nil)
      path = Waitmate.configuration.waiting_room_path
      path += "?#{{ticket: ticket}.to_query}" if ticket
      redirect_to(path)
    end
  end
end
