# frozen_string_literal: true

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "active_support/railtie"
require "rails/test_unit/railtie"

require "waitmate"

module Dummy
  class Application < Rails::Application
    config.root = File.expand_path("..", __dir__)
    config.load_defaults 7.1
    config.eager_load = false
    config.secret_key_base = "dummy_secret_key_base_for_testing_only_not_for_production"

    config.default_url_options = {host: "example.com"}
  end
end
