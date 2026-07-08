# frozen_string_literal: true

require "rails_helper"
require "fileutils"
require "socket"
require "tmpdir"
require "support/store_contract_examples"

RSpec.describe Waitmate::Store::Redis do
  before do
    TestRedisServer.ensure_running
  end

  after do
    redis = TestRedisServer.connection
    keys = redis.keys("waitmate:*")
    redis.del(*keys) if keys.any?
  rescue NameError
    # hide_const("Redis") removes the constant during the missing-gem example.
  end

  let(:store) { described_class.new(redis: TestRedisServer.connection) }

  it_behaves_like "a Waitmate store"

  describe "connection failures" do
    it "raises Waitmate::Store::ConnectionError when Redis is unreachable" do
      bad_redis = instance_double(::Redis)
      allow(bad_redis).to receive(:eval).and_raise(::Redis::CannotConnectError, "Connection refused")

      store = described_class.new(redis: bad_redis)

      expect {
        store.enqueue("checkout", "session-abc")
      }.to raise_error(Waitmate::Store::ConnectionError, /could not reach Redis/i)
    end

    it "raises Waitmate::Store::Error for other Redis errors" do
      bad_redis = instance_double(::Redis)
      allow(bad_redis).to receive(:eval).and_raise(::Redis::CommandError, "ERR syntax")

      store = described_class.new(redis: bad_redis)

      expect {
        store.enqueue("checkout", "session-abc")
      }.to raise_error(Waitmate::Store::Error, /Redis store error/i)
    end
  end

  describe "missing Redis gem" do
    it "raises a ConfigurationError when Redis is not defined" do
      hide_const("Redis")

      expect {
        described_class.new
      }.to raise_error(Waitmate::Store::ConfigurationError, /Redis gem is not available/i)
    end
  end
end

module TestRedisServer
  class << self
    def ensure_running
      return if @running || external_url?

      @port = find_free_port
      @dir = Dir.mktmpdir("waitmate-redis")
      @pid = spawn(
        "redis-server",
        "--port", @port.to_s,
        "--dir", @dir,
        "--daemonize", "no",
        "--save", "",
        "--appendonly", "no",
        out: File::NULL,
        err: File::NULL
      )

      wait_for_redis
      @running = true
    end

    def connection
      ensure_running

      if external_url?
        ::Redis.new(url: ENV.fetch("WAITMATE_REDIS_URL"))
      else
        ::Redis.new(port: @port)
      end
    end

    def shutdown
      return if external_url?
      return unless @pid

      Process.kill("TERM", @pid)
      Process.wait(@pid)
      FileUtils.remove_entry(@dir) if @dir && File.directory?(@dir)
      @running = false
      @pid = nil
    end

    private

    def external_url?
      ENV.key?("WAITMATE_REDIS_URL")
    end

    def find_free_port
      server = TCPServer.new("127.0.0.1", 0)
      port = server.addr[1]
      server.close
      port
    end

    def wait_for_redis
      50.times do
        ::Redis.new(port: @port).ping
        return
      rescue ::Redis::CannotConnectError
        sleep 0.1
      end

      raise "Redis test server failed to start on port #{@port}"
    end
  end
end

at_exit { TestRedisServer.shutdown }
