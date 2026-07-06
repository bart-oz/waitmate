# frozen_string_literal: true

Waitmate::Engine.routes.draw do
  get "room", to: "rooms#show"
  get "room/position", to: "rooms#position"
end
