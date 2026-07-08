# frozen_string_literal: true

begin
  require "redis" unless defined?(::Redis)
rescue LoadError
  # Redis is optional; instantiation without the gem raises ConfigurationError.
end

module Waitmate
  module Store
    # Redis-backed store contract implementation. All operations that touch
    # capacity or ordering run inside atomic Lua scripts so concurrent callers
    # cannot double-count or lose slots.
    #
    # Per-queue data model:
    #   waitmate:queue:{q}          - sorted set keyed by enqueue timestamp (FIFO)
    #   waitmate:waiting_expiry:{q} - sorted set keyed by expiry timestamp
    #   waitmate:active:{q}         - sorted set keyed by expiry timestamp
    class Redis
      KEY_PREFIX = "waitmate"
      LUA_SCRIPTS = {
        enqueue: <<~LUA,
          local queue_key = KEYS[1]
          local expiry_key = KEYS[2]
          local active_key = KEYS[3]
          local identity = ARGV[1]
          local now = tonumber(ARGV[2])
          local expiry = tonumber(ARGV[3])

          redis.call('ZREMRANGEBYSCORE', active_key, '-inf', now)

          if redis.call('ZRANK', active_key, identity) ~= false then
            return 0
          end

          local waiting_rank = redis.call('ZRANK', queue_key, identity)
          if waiting_rank ~= false then
            redis.call('ZADD', expiry_key, expiry, identity)
            return waiting_rank + 1
          end

          redis.call('ZADD', queue_key, now, identity)
          redis.call('ZADD', expiry_key, expiry, identity)
          return redis.call('ZRANK', queue_key, identity) + 1
        LUA

        position: <<~LUA,
          local queue_key = KEYS[1]
          local expiry_key = KEYS[2]
          local active_key = KEYS[3]
          local identity = ARGV[1]
          local now = tonumber(ARGV[2])

          redis.call('ZREMRANGEBYSCORE', active_key, '-inf', now)

          local expired = redis.call('ZRANGEBYSCORE', expiry_key, '-inf', now)
          for i = 1, #expired do
            redis.call('ZREM', queue_key, expired[i])
            redis.call('ZREM', expiry_key, expired[i])
          end

          if redis.call('ZRANK', active_key, identity) ~= false then
            return 0
          end

          local waiting_rank = redis.call('ZRANK', queue_key, identity)
          if waiting_rank ~= false then
            return waiting_rank + 1
          end

          return -1
        LUA

        active_count: <<~LUA,
          local active_key = KEYS[1]
          local now = tonumber(ARGV[1])

          redis.call('ZREMRANGEBYSCORE', active_key, '-inf', now)
          return redis.call('ZCARD', active_key)
        LUA

        admit: <<~LUA,
          local queue_key = KEYS[1]
          local expiry_key = KEYS[2]
          local active_key = KEYS[3]
          local now = tonumber(ARGV[1])
          local active_ttl = tonumber(ARGV[2])
          local max_concurrent = tonumber(ARGV[3])
          local count = tonumber(ARGV[4])

          redis.call('ZREMRANGEBYSCORE', active_key, '-inf', now)

          local expired_waiting = redis.call('ZRANGEBYSCORE', expiry_key, '-inf', now)
          for i = 1, #expired_waiting do
            redis.call('ZREM', queue_key, expired_waiting[i])
            redis.call('ZREM', expiry_key, expired_waiting[i])
          end

          local active_count = redis.call('ZCARD', active_key)
          local available = max_concurrent - active_count
          if available <= 0 then
            return {}
          end

          local admit_count = math.min(available, count)
          local waiting = redis.call('ZRANGE', queue_key, 0, admit_count - 1)
          if #waiting == 0 then
            return {}
          end

          local active_expiry = now + active_ttl
          for i = 1, #waiting do
            local identity = waiting[i]
            redis.call('ZREM', queue_key, identity)
            redis.call('ZREM', expiry_key, identity)
            redis.call('ZADD', active_key, active_expiry, identity)
          end

          return waiting
        LUA

        heartbeat: <<~LUA,
          local queue_key = KEYS[1]
          local expiry_key = KEYS[2]
          local active_key = KEYS[3]
          local identity = ARGV[1]
          local now = tonumber(ARGV[2])
          local ttl = tonumber(ARGV[3])

          if redis.call('ZRANK', active_key, identity) ~= false then
            redis.call('ZADD', active_key, now + ttl, identity)
            return 1
          end

          if redis.call('ZRANK', queue_key, identity) ~= false then
            redis.call('ZADD', expiry_key, now + ttl, identity)
            return 1
          end

          return 0
        LUA

        expire_stale: <<~LUA
          local queue_key = KEYS[1]
          local expiry_key = KEYS[2]
          local active_key = KEYS[3]
          local now = tonumber(ARGV[1])

          local expired_waiting = redis.call('ZRANGEBYSCORE', expiry_key, '-inf', now)
          for i = 1, #expired_waiting do
            redis.call('ZREM', queue_key, expired_waiting[i])
            redis.call('ZREM', expiry_key, expired_waiting[i])
          end

          local active_removed = redis.call('ZREMRANGEBYSCORE', active_key, '-inf', now)

          return {#expired_waiting, active_removed}
        LUA
      }.freeze

      def initialize(redis: nil, config: Waitmate.configuration)
        unless defined?(::Redis)
          raise ConfigurationError,
            "Redis gem is not available. Add `gem 'redis'` to your Gemfile to use the Redis adapter."
        end

        @config = config
        @redis = redis || ::Redis.new
      end

      attr_reader :redis

      def enqueue(queue_name, identity, ttl: nil)
        ttl ||= @config.queue_ttl
        now = current_timestamp
        expiry = now + ttl

        eval_script(
          :enqueue,
          keys: [queue_key(queue_name), expiry_key(queue_name), active_key(queue_name)],
          argv: [identity.to_s, now, expiry]
        )
      end

      def position(queue_name, identity)
        rank = eval_script(
          :position,
          keys: [queue_key(queue_name), expiry_key(queue_name), active_key(queue_name)],
          argv: [identity.to_s, current_timestamp]
        )

        (rank == -1) ? nil : rank
      end

      def active_count(queue_name)
        eval_script(
          :active_count,
          keys: [active_key(queue_name)],
          argv: [current_timestamp]
        )
      end

      def admit(queue_name, max_concurrent, count: max_concurrent)
        eval_script(
          :admit,
          keys: [queue_key(queue_name), expiry_key(queue_name), active_key(queue_name)],
          argv: [current_timestamp, @config.queue_ttl, max_concurrent, count]
        )
      end

      def release(queue_name, identity)
        result = with_redis do |redis|
          redis.zrem(active_key(queue_name), identity.to_s)
        end
        !!result
      end

      def heartbeat(queue_name, identity, ttl: nil)
        ttl ||= @config.queue_ttl
        result = eval_script(
          :heartbeat,
          keys: [queue_key(queue_name), expiry_key(queue_name), active_key(queue_name)],
          argv: [identity.to_s, current_timestamp, ttl]
        )
        result == 1
      end

      def expire_stale(queue_name)
        waiting, active = eval_script(
          :expire_stale,
          keys: [queue_key(queue_name), expiry_key(queue_name), active_key(queue_name)],
          argv: [current_timestamp]
        )

        {waiting: waiting, active: active}
      end

      private

      def queue_key(queue_name)
        "#{KEY_PREFIX}:queue:#{queue_name}"
      end

      def expiry_key(queue_name)
        "#{KEY_PREFIX}:waiting_expiry:#{queue_name}"
      end

      def active_key(queue_name)
        "#{KEY_PREFIX}:active:#{queue_name}"
      end

      def current_timestamp
        ::Time.now.to_f
      end

      def eval_script(name, keys:, argv:)
        with_redis do |redis|
          redis.eval(LUA_SCRIPTS[name], keys: keys, argv: argv)
        end
      end

      def with_redis
        yield @redis
      rescue ::Redis::CannotConnectError, ::Redis::ConnectionError, ::Redis::TimeoutError => e
        raise ConnectionError,
          "Waitmate could not reach Redis (#{e.class}: #{e.message}). " \
          "Verify REDIS_URL or the configured Redis server."
      rescue ::Redis::BaseError => e
        raise Error, "Waitmate Redis store error (#{e.class}: #{e.message})"
      end
    end
  end
end
