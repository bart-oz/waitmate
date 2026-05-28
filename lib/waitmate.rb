# frozen_string_literal: true

require_relative "waitmate/version"
require_relative "waitmate/configuration"
require_relative "waitmate/engine" if defined?(Rails::Engine)

module Waitmate
  class Error < StandardError; end

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
