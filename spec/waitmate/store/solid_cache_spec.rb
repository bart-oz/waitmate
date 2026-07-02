# frozen_string_literal: true

require "rails_helper"
require "support/store_contract_examples"

RSpec.describe Waitmate::Store::SolidCache do
  let(:store) { described_class.new }

  it_behaves_like "a Waitmate store"

  describe "adapter dispatch" do
    after do
      Waitmate::Store.reset_adapter!
      Waitmate.reset_configuration!
    end

    it "is built by Waitmate::Store when adapter is :solid_cache" do
      Waitmate.configure do |config|
        config.adapter = :solid_cache
      end

      expect(Waitmate::Store.adapter).to be_a(described_class)
    end
  end

  describe "connection failures" do
    it "raises Waitmate::Store::ConnectionError when the database is unreachable" do
      allow(::SolidCache::Entry).to receive(:write).and_raise(ActiveRecord::ConnectionNotEstablished, "No connection")

      expect {
        store.enqueue("checkout", "session-abc")
      }.to raise_error(Waitmate::Store::ConnectionError, /could not reach Solid Cache/i)
    end

    it "raises Waitmate::Store::Error for other database errors" do
      allow(::SolidCache::Entry).to receive(:write).and_raise(NoMethodError, "undefined method")

      expect {
        store.enqueue("checkout", "session-abc")
      }.to raise_error(Waitmate::Store::Error, /Solid Cache store error/i)
    end
  end

  describe "missing Solid Cache gem" do
    it "raises a ConfigurationError when SolidCache is not defined" do
      hide_const("SolidCache")

      expect {
        described_class.new
      }.to raise_error(Waitmate::Store::ConfigurationError, /Solid Cache gem is not available/i)
    end
  end
end
