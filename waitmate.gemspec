# frozen_string_literal: true

require_relative "lib/waitmate/version"

Gem::Specification.new do |spec|
  spec.name = "waitmate"
  spec.version = Waitmate::VERSION
  spec.authors = ["BartOz"]
  spec.email = ["bartek.ozdoba@gmail.com"]
  spec.summary = "Virtual waiting room for Rails applications"
  spec.description = "Protects expensive controller actions from thundering-herd overload by queuing overflow users, issuing signed admission tickets, and letting users wait on a lightweight Engine-provided page."
  spec.homepage = "https://github.com/bart-oz/waitmate"
  spec.license = "MIT"
  spec.files = Dir["lib/**/*", "app/**/*", "config/**/*", "README.md", "LICENSE.txt", "bin/*"]
  spec.require_paths = ["lib"]
  spec.bindir = "bin"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.required_ruby_version = ">= #{Waitmate::RUBY_MINIMUM_VERSION}"
  spec.add_dependency "rails", ">= #{Waitmate::RAILS_MINIMUM_VERSION}"
end
