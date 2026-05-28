# frozen_string_literal: true

require "rails_helper"

RSpec.describe Waitmate::Engine, type: :request do
  it "is a Rails::Engine" do
    expect(described_class).to be < Rails::Engine
  end

  it "isolates the Waitmate namespace" do
    expect(described_class.isolated?).to be true
  end
end
