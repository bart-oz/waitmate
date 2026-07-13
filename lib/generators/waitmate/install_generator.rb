# frozen_string_literal: true

module Waitmate
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates a Waitmate initializer in config/initializers/waitmate.rb"

      def copy_initializer
        template "waitmate.rb", "config/initializers/waitmate.rb"
      end
    end
  end
end
