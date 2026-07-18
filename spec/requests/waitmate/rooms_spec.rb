# frozen_string_literal: true

require "rails_helper"

RSpec.describe Waitmate::RoomsController, type: :request do
  before do
    Waitmate.configuration.adapter = :solid_cache
    Waitmate::Store.reset_adapter!
    fill_capacity
  end

  after do
    if defined?(::SolidCache::Entry)
      ::SolidCache::Entry.where("key LIKE ?", "waitmate:%").delete_all
    end
    Waitmate::Store.reset_adapter!
    Waitmate.reset_configuration!
  end

  def fill_capacity
    Waitmate::Store.enqueue("index", "other-1")
    Waitmate::Store.enqueue("index", "other-2")
    Waitmate::Store.admit("index", 2)
  end

  def room_query(ticket:, queue:, target: "/waitmate_test/index")
    {ticket: ticket, queue: queue, target: target}
  end

  def room_params_from_redirect
    URI.decode_www_form(URI(response.location).query || "").to_h
  end

  describe "GET /waitmate/room" do
    it "renders the waiting page when the user is queued" do
      get "/waitmate_test/index"
      expect(response).to redirect_to(%r{/waitmate/room\?.*ticket=})

      get response.location
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You're in line")
      expect(response.body).to include("Place in line")
      expect(response.body).to include('<meta name="turbo-visit-control" content="reload">')
    end

    it "redirects back to the protected target when the user is admitted" do
      get "/waitmate_test/index"
      params = room_params_from_redirect

      Waitmate::Store.release("index", "other-1")
      Waitmate::Store.admit("index", 2)

      get "/waitmate/room", params: room_query(ticket: params["ticket"], queue: params["queue"])

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(%r{/waitmate_test/index\?ticket=})
    end

    it "shows a generic error page for an invalid ticket" do
      get "/waitmate/room", params: room_query(ticket: "not-valid", queue: "index")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Still holding your place")
      expect(response.body).not_to include("not-valid")
    end

    it "calls Store.heartbeat when rendering the waiting page" do
      get "/waitmate_test/index"
      params = room_params_from_redirect

      expect(Waitmate::Store).to receive(:heartbeat).once.and_call_original
      get "/waitmate/room", params: room_query(ticket: params["ticket"], queue: params["queue"])

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("You're in line")
    end

    it "shows a generic error page for an unsafe target when admitted" do
      get "/waitmate_test/index"
      params = room_params_from_redirect

      Waitmate::Store.release("index", "other-1")
      Waitmate::Store.admit("index", 2)

      get "/waitmate/room", params: room_query(ticket: params["ticket"], queue: params["queue"], target: "//evil.com")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Still holding your place")
    end
  end

  describe "GET /waitmate/room/position" do
    it "returns position and admitted:false while waiting" do
      get "/waitmate_test/index"
      params = room_params_from_redirect

      get "/waitmate/room/position", params: {ticket: params["ticket"], queue: params["queue"]}

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["position"]).to eq(1)
      expect(body["admitted"]).to be false
      expect(body["retry"]).to eq(Waitmate.configuration.polling_interval)
      expect(response.headers["Cache-Control"]).to include("private")
    end

    it "returns admitted:true when the user is active" do
      get "/waitmate_test/index"
      params = room_params_from_redirect

      Waitmate::Store.release("index", "other-1")
      Waitmate::Store.admit("index", 2)

      get "/waitmate/room/position", params: {ticket: params["ticket"], queue: params["queue"]}

      body = JSON.parse(response.body)
      expect(body["position"]).to eq(0)
      expect(body["admitted"]).to be true
    end

    it "returns coarse values for an invalid ticket" do
      get "/waitmate/room/position", params: {ticket: "bad-token", queue: "index"}

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["position"]).to be_nil
      expect(body["admitted"]).to be false
    end

    it "does not call Store.active_count, Store.admit, or Store.expire_stale" do
      get "/waitmate_test/index"
      params = room_params_from_redirect

      allow(Waitmate::Store).to receive(:heartbeat).and_return(true)
      allow(Waitmate::Store).to receive(:position).and_return(1)
      expect(Waitmate::Store).not_to receive(:active_count)
      expect(Waitmate::Store).not_to receive(:admit)
      expect(Waitmate::Store).not_to receive(:expire_stale)

      get "/waitmate/room/position", params: {ticket: params["ticket"], queue: params["queue"]}

      expect(response).to have_http_status(:ok)
    end

    it "calls Store.heartbeat on each poll" do
      get "/waitmate_test/index"
      params = room_params_from_redirect

      expect(Waitmate::Store).to receive(:heartbeat).once.and_call_original
      get "/waitmate/room/position", params: {ticket: params["ticket"], queue: params["queue"]}
      expect(response).to have_http_status(:ok)
    end
  end

  describe "concern-to-room-to-target flow" do
    it "redirects through the room and back to the protected action" do
      get "/waitmate_test/index"
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(%r{/waitmate/room\?.*ticket=})
      room_url = response.location
      params = room_params_from_redirect

      get room_url
      expect(response).to have_http_status(:ok)

      Waitmate::Store.release("index", "other-1")
      Waitmate::Store.admit("index", 2)

      get "/waitmate/room/position", params: {ticket: params["ticket"], queue: params["queue"]}
      body = JSON.parse(response.body)
      expect(body["admitted"]).to be true

      get room_url
      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(%r{/waitmate_test/index\?ticket=})

      get response.location
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("admitted")
    end
  end
end
