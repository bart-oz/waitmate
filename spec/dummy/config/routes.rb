# frozen_string_literal: true

Rails.application.routes.draw do
  mount Waitmate::Engine => "/waitmate"

  get "waitmate_test/index", to: "waitmate_test#index"
  get "waitmate_test/public", to: "waitmate_test#public"
  post "waitmate_test/create", to: "waitmate_test#create"
end
