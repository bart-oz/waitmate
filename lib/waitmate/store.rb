# frozen_string_literal: true

module Waitmate
  # Public seam for all queue/storage operations. Host controllers and engine UI
  # call +Waitmate::Store+, never a concrete adapter.
  module Store
    class Error < Waitmate::Error; end
    class ConfigurationError < Error; end
    class ConnectionError < Error; end

    @adapter = nil

    class << self
      # enqueue(queue_name, identity, ttl: nil) -> Integer (1-based position) or 0 (already active)
      def enqueue(queue_name, identity, ttl: nil)
        adapter.enqueue(queue_name, identity, ttl: ttl)
      end

      # position(queue_name, identity) -> Integer (1-based), 0 (active), or nil
      def position(queue_name, identity)
        adapter.position(queue_name, identity)
      end

      # active_count(queue_name) -> Integer
      def active_count(queue_name)
        adapter.active_count(queue_name)
      end

      # admit(queue_name, max_concurrent, count: max_concurrent) -> Array<String>
      def admit(queue_name, max_concurrent, count: max_concurrent)
        adapter.admit(queue_name, max_concurrent, count: count)
      end

      # release(queue_name, identity) -> Boolean
      def release(queue_name, identity)
        adapter.release(queue_name, identity)
      end

      # heartbeat(queue_name, identity, ttl: nil) -> Boolean
      def heartbeat(queue_name, identity, ttl: nil)
        adapter.heartbeat(queue_name, identity, ttl: ttl)
      end

      # expire_stale(queue_name) -> Hash {waiting: Integer, active: Integer}
      def expire_stale(queue_name)
        adapter.expire_stale(queue_name)
      end

      def adapter
        @adapter ||= build_adapter(Waitmate.configuration.adapter)
      end

      attr_writer :adapter

      def reset_adapter!
        @adapter = nil
      end

      private

      def build_adapter(name)
        case name
        when :redis
          Redis.new
        when :solid_cache
          SolidCache.new
        else
          raise ConfigurationError, "Unknown Waitmate adapter: #{name.inspect}"
        end
      end
    end
  end
end
