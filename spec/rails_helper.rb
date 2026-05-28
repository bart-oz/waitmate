# frozen_string_literal: true

require "spec_helper"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "active_support/railtie"
require "rails/test_unit/railtie"

ENV["RAILS_ENV"] = "test"

# Require waitmate after Rails is available so the Engine loads.
# If waitmate was already required without Rails (e.g. by a unit spec),
# the engine guard in lib/waitmate.rb skipped it; load it explicitly.
require "waitmate"
require "waitmate/engine" unless defined?(Waitmate::Engine)

require_relative "dummy/config/environment"
require "rspec/rails"

Rails.cache = ActiveSupport::Cache.lookup_store(:memory_store)

RSpec.configure do |config|
  config.infer_spec_type_from_file_location!

  config.before(:each) do
    Rails.cache.clear if defined?(Rails.cache) && Rails.cache
  end
end
