# frozen_string_literal: true

require "rails_helper"
require "rails/generators/test_case"
require "generators/waitmate/install_generator"

RSpec.describe Waitmate::Generators::InstallGenerator do
  include FileUtils
  include Rails::Generators::Testing::Behavior
  include Rails::Generators::Testing::Assertions

  tests(described_class)
  destination(File.expand_path("../tmp/generator", __dir__))

  before { prepare_destination }

  after { FileUtils.rm_rf(destination_root) }

  it "copies an initializer with all config keys" do
    run_generator

    initializer = File.read(File.join(destination_root, "config/initializers/waitmate.rb"))
    expect(initializer).to include("Waitmate.configure")
    expect(initializer).to match(/config\.adapter\s*=\s*:redis/)
    expect(initializer).to match(/config\.queue_ttl\s*=\s*300/)
    expect(initializer).to match(/config\.polling_interval\s*=\s*5/)
    expect(initializer).to match(/config\.ticket_ttl\s*=\s*120/)
    expect(initializer).to match(/config\.waiting_room_path\s*=\s*"\/waitmate\/room"/)
  end

  it "is discoverable as waitmate:install" do
    expect(Rails::Generators.find_by_namespace("waitmate:install")).to eq(described_class)
  end
end
