# frozen_string_literal: true

require "rails_helper"

RSpec.describe Waitmate::Ticket do
  let(:queue_name) { "checkout" }
  let(:session_id) { "sess_abc123" }
  let(:other_session_id) { "sess_xyz789" }

  describe ".issue" do
    it "returns an encrypted token string" do
      token = described_class.issue(queue_name: queue_name, session_id: session_id)

      expect(token).to be_a(String)
      expect(token).not_to be_empty
      expect(token).not_to include(session_id)
    end

    it "embeds a SHA256 digest of the session identity, not the raw session id" do
      token = described_class.issue(queue_name: queue_name, session_id: session_id)
      encryptor = ticket_encryptor
      payload = encryptor.decrypt_and_verify(token, purpose: described_class::PURPOSE)

      expect(payload).not_to have_key("session_id")
      expect(payload).not_to have_key(:session_id)
      expect(payload).not_to have_key("ip")
      expect(payload["identity_digest"]).to eq(Digest::SHA256.hexdigest(session_id))
    end

    it "binds the token to the queue name" do
      token = described_class.issue(queue_name: queue_name, session_id: session_id)
      payload = ticket_encryptor.decrypt_and_verify(token, purpose: described_class::PURPOSE)

      expect(payload["queue_name"]).to eq(queue_name)
    end
  end

  describe ".verify" do
    context "with a valid token" do
      it "returns a successful result on issue->verify roundtrip" do
        token = described_class.issue(queue_name: queue_name, session_id: session_id)
        result = described_class.verify(token: token, queue_name: queue_name, session_id: session_id)

        expect(result).to be_a(Waitmate::Ticket::Result)
        expect(result.success?).to be true
        expect(result.reason).to be_nil
      end
    end

    context "with a tampered token" do
      it "returns a failure result" do
        token = described_class.issue(queue_name: queue_name, session_id: session_id)
        tampered = token.dup.tap { |t| t[-3..] = (t[-3].ord ^ 1).chr }
        result = described_class.verify(token: tampered, queue_name: queue_name, session_id: session_id)

        expect(result.success?).to be false
        expect(result.reason).to eq(:invalid)
      end
    end

    context "with an expired token" do
      it "returns a failure result" do
        token = nil
        travel_to(1.second.ago) do
          token = described_class.issue(queue_name: queue_name, session_id: session_id)
        end

        travel_to(Time.current + Waitmate.configuration.ticket_ttl + 1) do
          result = described_class.verify(token: token, queue_name: queue_name, session_id: session_id)

          expect(result.success?).to be false
          expect(result.reason).to eq(:invalid)
        end
      end
    end

    context "with a token issued for a different queue" do
      it "returns a failure result" do
        token = described_class.issue(queue_name: queue_name, session_id: session_id)
        result = described_class.verify(token: token, queue_name: "other_queue", session_id: session_id)

        expect(result.success?).to be false
        expect(result.reason).to eq(:invalid)
      end
    end

    context "with a token issued for a different identity" do
      it "returns a failure result" do
        token = described_class.issue(queue_name: queue_name, session_id: session_id)
        result = described_class.verify(token: token, queue_name: queue_name, session_id: other_session_id)

        expect(result.success?).to be false
        expect(result.reason).to eq(:invalid)
      end
    end

    context "with a token issued by a different purpose" do
      it "returns a failure result" do
        other_encryptor = ActiveSupport::MessageEncryptor.new(
          Rails.application.key_generator.generate_key(described_class::SALT, described_class::KEY_LENGTH)
        )
        token = other_encryptor.encrypt_and_sign({"queue_name" => queue_name}, purpose: "other:purpose")
        result = described_class.verify(token: token, queue_name: queue_name, session_id: session_id)

        expect(result.success?).to be false
        expect(result.reason).to eq(:invalid)
      end
    end

    context "with nil token" do
      it "returns a failure result" do
        result = described_class.verify(token: nil, queue_name: queue_name, session_id: session_id)

        expect(result.success?).to be false
        expect(result.reason).to eq(:invalid)
      end
    end
  end

  def ticket_encryptor
    ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key(described_class::SALT, described_class::KEY_LENGTH)
    )
  end
end
