# frozen_string_literal: true

Rails.application.routes.draw do
  mount Waitmate::Engine => "/waitmate"
end
