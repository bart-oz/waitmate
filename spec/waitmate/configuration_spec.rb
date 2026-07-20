# frozen_string_literal: true

require "waitmate"

RSpec.describe Waitmate do
  it "boots through require" do
    expect(Waitmate::VERSION).to eq("0.2.0")
  end

  describe ".configuration" do
    it "returns a Configuration instance" do
      expect(Waitmate.configuration).to be_a(Waitmate::Configuration)
    end

    it "memoizes the configuration" do
      config = Waitmate.configuration
      expect(Waitmate.configuration).to equal(config)
    end
  end

  describe ".configure" do
    after { Waitmate.reset_configuration! }

    it "yields the configuration object" do
      expect { |b| Waitmate.configure(&b) }.to yield_with_args(Waitmate::Configuration)
    end

    it "allows setting configuration values" do
      Waitmate.configure do |config|
        config.adapter = :solid_cache
        config.queue_ttl = 600
      end

      expect(Waitmate.configuration.adapter).to eq(:solid_cache)
      expect(Waitmate.configuration.queue_ttl).to eq(600)
    end
  end

  describe ".reset_configuration!" do
    it "resets configuration to defaults" do
      Waitmate.configure do |config|
        config.adapter = :solid_cache
        config.queue_ttl = 600
      end

      Waitmate.reset_configuration!

      expect(Waitmate.configuration.adapter).to eq(:redis)
      expect(Waitmate.configuration.queue_ttl).to eq(300)
    end
  end
end

RSpec.describe Waitmate::Configuration do
  subject(:config) { described_class.new }

  describe "#adapter" do
    it "defaults to :redis" do
      expect(config.adapter).to eq(:redis)
    end

    it "can be set to :solid_cache" do
      config.adapter = :solid_cache
      expect(config.adapter).to eq(:solid_cache)
    end
  end

  describe "#queue_ttl" do
    it "defaults to 300" do
      expect(config.queue_ttl).to eq(300)
    end

    it "can be set" do
      config.queue_ttl = 600
      expect(config.queue_ttl).to eq(600)
    end
  end

  describe "#polling_interval" do
    it "defaults to 5" do
      expect(config.polling_interval).to eq(5)
    end

    it "can be set" do
      config.polling_interval = 10
      expect(config.polling_interval).to eq(10)
    end
  end

  describe "#ticket_ttl" do
    it "defaults to 120" do
      expect(config.ticket_ttl).to eq(120)
    end

    it "can be set" do
      config.ticket_ttl = 60
      expect(config.ticket_ttl).to eq(60)
    end
  end
end
