# frozen_string_literal: true

require_relative "waitmate/version"

module Waitmate
  class Error < StandardError; end
end

require_relative "waitmate/configuration"
require_relative "waitmate/ticket"
require_relative "waitmate/store"
require_relative "waitmate/store/redis"
require_relative "waitmate/store/solid_cache"
require_relative "waitmate/controller_concern"
require_relative "waitmate/engine" if defined?(Rails::Engine)

module Waitmate
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
