# frozen_string_literal: true

require "rails_helper"

RSpec.describe Waitmate::ControllerConcern, type: :request do
  before do
    Waitmate.configuration.adapter = :solid_cache
    Waitmate::Store.reset_adapter!
  end

  after do
    Waitmate::Store.reset_adapter!
    Waitmate.reset_configuration!
  end

  describe "macro declaration" do
    it "allows controllers to declare a waiting room for selected actions" do
      expect(WaitmateTestController).to respond_to(:wait_room)
    end

    it "does not gate actions without the macro" do
      get "/waitmate_test/public"

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("public")
    end
  end

  describe "admitted path" do
    it "proceeds to the protected action when active count is below capacity" do
      get "/waitmate_test/index"

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("admitted")
    end
  end

  describe "queued path" do
    it "redirects to the waiting room when active count reaches capacity" do
      Waitmate::Store.enqueue("index", "other-1")
      Waitmate::Store.enqueue("index", "other-2")
      Waitmate::Store.admit("index", 2)

      get "/waitmate_test/index"

      expect(response).to redirect_to(%r{/waitmate/room})
      expect(response.location).to include("ticket=")
    end
  end

  describe "returned path" do
    it "proceeds when a valid ticket is redeemed into active capacity" do
      Waitmate::Store.enqueue("index", "other-1")
      Waitmate::Store.enqueue("index", "other-2")
      Waitmate::Store.admit("index", 2)

      get "/waitmate_test/index"
      expect(response).to redirect_to(%r{/waitmate/room\?ticket=})
      token = URI.decode_www_form(URI(response.location).query || "").to_h["ticket"]

      Waitmate::Store.release("index", "other-1")
      Waitmate::Store.admit("index", 2)

      get "/waitmate_test/index", params: {ticket: token}

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("admitted")
    end
  end

  describe "rejected path" do
    it "redirects to the waiting room when the ticket is invalid" do
      get "/waitmate_test/index", params: {ticket: "not-a-valid-ticket"}

      expect(response).to redirect_to(%r{/waitmate/room})
    end

    it "redirects when the ticket is for a different queue" do
      token = Waitmate::Ticket.issue(queue_name: "other", session_id: "any-session")

      get "/waitmate_test/index", params: {ticket: token}

      expect(response).to redirect_to(%r{/waitmate/room})
      expect(response.body).not_to eq("admitted")
    end

    it "redirects when the ticket is for a different session" do
      token = Waitmate::Ticket.issue(queue_name: "index", session_id: "other-session")

      get "/waitmate_test/index", params: {ticket: token}

      expect(response).to redirect_to(%r{/waitmate/room})
      expect(response.body).not_to eq("admitted")
    end
  end
end
