# frozen_string_literal: true

require "digest"
require "active_support"
require "active_support/message_encryptor"

module Waitmate
  module Ticket
    PURPOSE = "waitmate:ticket"
    SALT = "waitmate ticket v1"
    KEY_LENGTH = 32

    class Result
      attr_reader :reason

      def initialize(success:, reason: nil)
        @success = success
        @reason = reason
      end

      def success?
        @success
      end
    end

    class << self
      def issue(queue_name:, session_id:)
        encryptor.encrypt_and_sign(
          payload(queue_name, session_id),
          expires_in: Waitmate.configuration.ticket_ttl,
          purpose: PURPOSE
        )
      end

      def verify(token:, queue_name:, session_id:)
        data = encryptor.decrypt_and_verify(token.to_s, purpose: PURPOSE)
        return failure(:invalid) unless valid_payload?(data, queue_name, session_id)

        success
      rescue ActiveSupport::MessageEncryptor::InvalidMessage
        failure(:invalid)
      end

      private

      def payload(queue_name, session_id)
        {
          "queue_name" => queue_name.to_s,
          "identity_digest" => identity_digest(session_id)
        }
      end

      def identity_digest(session_id)
        Digest::SHA256.hexdigest(session_id.to_s)
      end

      def valid_payload?(data, queue_name, session_id)
        data.is_a?(Hash) &&
          data["queue_name"] == queue_name.to_s &&
          data["identity_digest"] == identity_digest(session_id)
      end

      def encryptor
        @encryptor ||= ActiveSupport::MessageEncryptor.new(
          Rails.application.key_generator.generate_key(SALT, KEY_LENGTH)
        )
      end

      def success
        Result.new(success: true, reason: nil)
      end

      def failure(reason)
        Result.new(success: false, reason: reason)
      end
    end
  end
end
