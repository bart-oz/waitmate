# frozen_string_literal: true

require "waitmate"

RSpec.describe Waitmate::Store do
  after do
    described_class.reset_adapter!
    Waitmate.reset_configuration!
  end

  describe ".adapter" do
    it "builds the Redis adapter by default" do
      expect(described_class.adapter).to be_a(Waitmate::Store::Redis)
    end

    it "raises ConfigurationError for unknown adapters" do
      Waitmate.configure do |config|
        config.adapter = :unknown
      end

      expect {
        described_class.adapter
      }.to raise_error(Waitmate::Store::ConfigurationError, /Unknown Waitmate adapter/i)
    end

    it "allows injection of a custom adapter" do
      fake = instance_double(Waitmate::Store::Redis)
      described_class.adapter = fake

      expect(described_class.adapter).to equal(fake)
    end
  end

  describe "contract delegation" do
    let(:fake_adapter) { instance_double(Waitmate::Store::Redis) }

    before do
      described_class.adapter = fake_adapter
    end

    it "delegates enqueue" do
      expect(fake_adapter).to receive(:enqueue).with("q", "id", ttl: nil)
      described_class.enqueue("q", "id")
    end

    it "delegates position" do
      expect(fake_adapter).to receive(:position).with("q", "id").and_return(1)
      expect(described_class.position("q", "id")).to eq(1)
    end

    it "delegates active_count" do
      expect(fake_adapter).to receive(:active_count).with("q").and_return(0)
      expect(described_class.active_count("q")).to eq(0)
    end

    it "delegates admit" do
      expect(fake_adapter).to receive(:admit).with("q", 5, count: 5).and_return(["id"])
      expect(described_class.admit("q", 5)).to eq(["id"])
    end

    it "delegates release" do
      expect(fake_adapter).to receive(:release).with("q", "id").and_return(true)
      expect(described_class.release("q", "id")).to be true
    end

    it "delegates heartbeat" do
      expect(fake_adapter).to receive(:heartbeat).with("q", "id", ttl: nil)
      described_class.heartbeat("q", "id")
    end

    it "delegates expire_stale" do
      expect(fake_adapter).to receive(:expire_stale).with("q").and_return(waiting: 0, active: 0)
      expect(described_class.expire_stale("q")).to eq(waiting: 0, active: 0)
    end
  end
end
