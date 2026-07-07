# frozen_string_literal: true

require "digest"

begin
  require "solid_cache" if defined?(Rails)
rescue LoadError
  # Solid Cache is optional; instantiation without the gem raises ConfigurationError.
end

module Waitmate
  module Store
    # SQL-backed fallback adapter built on top of SolidCache::Entry.
    #
    # Solid Cache is a fixed-schema key/value store, so Waitmate queue state
    # is separated into two key prefixes:
    #   waitmate:waiting:{queue}:{identity}  — waiting entries
    #   waitmate:active:{queue}:{identity}   — admitted entries
    #
    # This mirrors the Redis adapter's separate sorted sets and lets SQL
    # +LIKE+ narrow scans to one state before Ruby-side JSON parsing.
    # Active scans are bounded by +max_concurrent+; waiting scans are
    # bounded by queue depth ahead of the target entry.
    #
    # FIFO ordering relies on an +enqueued_at+ timestamp stored in the JSON
    # value, avoiding reliance on the binary +created_at+ column which has
    # cross-Rails-version comparison issues.
    #
    # Single-key lookups use +SolidCache::Entry.read+ / +delete_by_key+
    # which operate on the indexed +key_hash+ integer column, avoiding
    # binary +key+ column comparison entirely.
    #
    # Admission is serialized per queue with a mutex row so capacity
    # accounting never follows a read-modify-write path under concurrency.
    class SolidCache
      KEY_PREFIX = "waitmate"

      def initialize(config: Waitmate.configuration)
        begin
          require "solid_cache" unless defined?(::SolidCache)
        rescue LoadError
          # Fall through to the contract check below.
        end

        unless defined?(::SolidCache::Entry)
          raise ConfigurationError,
            "Solid Cache gem is not available. Add `gem 'solid_cache'` to your Gemfile " \
            "to use the Solid Cache adapter."
        end

        @queue_ttl = config.queue_ttl
      end

      # enqueue(queue_name, identity, ttl: nil) -> Integer (1-based position) or 0 (already active)
      def enqueue(queue_name, identity, ttl: nil)
        ttl ||= @queue_ttl
        now = current_timestamp
        expires_at = now + ttl
        a_key = active_entry_key(queue_name, identity)
        w_key = waiting_entry_key(queue_name, identity)

        with_ar do
          # Already active and not expired?
          active_value = read_value(a_key)
          if active_value
            return 0 if active_value["expires_at"] > now
          end

          # Already waiting and not expired?
          waiting_value = read_value(w_key)
          if waiting_value
            if waiting_value["expires_at"] > now
              waiting_value["expires_at"] = expires_at
              ::SolidCache::Entry.write(w_key, waiting_value.to_json)
              return waiting_position(queue_name, waiting_value["enqueued_at"], now)
            end
            # Expired waiting entry — delete so the new write gets a fresh enqueued_at
            ::SolidCache::Entry.delete_by_key(w_key)
          end

          # New entry
          value = {state: "waiting", expires_at: expires_at, enqueued_at: now}
          ::SolidCache::Entry.write(w_key, value.to_json)
          waiting_position(queue_name, now, now)
        end
      end

      # position(queue_name, identity) -> Integer (1-based), 0 (active), or nil
      def position(queue_name, identity)
        now = current_timestamp
        a_key = active_entry_key(queue_name, identity)
        w_key = waiting_entry_key(queue_name, identity)

        with_ar do
          # Check active
          active_value = read_value(a_key)
          if active_value
            if active_value["expires_at"] <= now
              ::SolidCache::Entry.delete_by_key(a_key)
              return nil
            end
            return 0
          end

          # Check waiting
          waiting_value = read_value(w_key)
          if waiting_value
            if waiting_value["expires_at"] <= now
              ::SolidCache::Entry.delete_by_key(w_key)
              return nil
            end
            return waiting_position(queue_name, waiting_value["enqueued_at"], now)
          end

          nil
        end
      end

      # active_count(queue_name) -> Integer
      def active_count(queue_name)
        now = current_timestamp

        with_ar do
          active_count_internal(queue_name, now)
        end
      end

      # admit(queue_name, max_concurrent, count: max_concurrent) -> Array<String>
      def admit(queue_name, max_concurrent, count: max_concurrent)
        now = current_timestamp
        active_ttl = @queue_ttl

        with_ar do
          admitted = []

          ActiveRecord::Base.transaction do
            ensure_mutex(queue_name)
            expire_stale_internal(queue_name, now)

            active = active_count_internal(queue_name, now)
            available = max_concurrent - active
            break admitted if available <= 0

            admit_count = [available, count].min

            # Separate waiting prefix guarantees all returned rows are waiting.
            # No Ruby-side state filter needed — fixes the S2-NEWBUG capacity bug.
            # Sort by enqueued_at from the JSON value for FIFO ordering.
            # uncached is required because SolidCache's own write/delete methods do
            # not dirty the Rails query cache, so a subsequent scan in the same
            # request (e.g. release → admit) could read stale waiting rows.
            waiting = ::SolidCache::Entry.uncached do
              ::SolidCache::Entry
                .where("key LIKE ?", waiting_key_pattern(queue_name))
                .to_a
                .map { |entry| [entry, parse_value(entry.value, key: entry.key)] }
                .select { |_, value| value["expires_at"] > now }
                .sort_by { |_, value| value["enqueued_at"] }
                .first(admit_count)
            end

            waiting.each do |entry, value|
              identity = identity_from_key(entry.key, queue_name)
              value["state"] = "active"
              value["expires_at"] = now + active_ttl
              ::SolidCache::Entry.delete_by_key(waiting_entry_key(queue_name, identity))
              ::SolidCache::Entry.write(active_entry_key(queue_name, identity), value.to_json)
              admitted << identity
            end
          end

          admitted
        end
      end

      # release(queue_name, identity) -> Boolean
      def release(queue_name, identity)
        key = active_entry_key(queue_name, identity)

        with_ar do
          result = ::SolidCache::Entry.delete_by_key(key)
          result.is_a?(Integer) ? result > 0 : result
        end
      end

      # heartbeat(queue_name, identity, ttl: nil) -> Boolean
      def heartbeat(queue_name, identity, ttl: nil)
        ttl ||= @queue_ttl
        now = current_timestamp
        w_key = waiting_entry_key(queue_name, identity)
        a_key = active_entry_key(queue_name, identity)

        with_ar do
          # Check waiting first
          value = read_value(w_key)
          if value
            return false if value["expires_at"] <= now
            value["expires_at"] = now + ttl
            ::SolidCache::Entry.write(w_key, value.to_json)
            return true
          end

          # Check active
          value = read_value(a_key)
          if value
            return false if value["expires_at"] <= now
            value["expires_at"] = now + ttl
            ::SolidCache::Entry.write(a_key, value.to_json)
            return true
          end

          false
        end
      end

      # expire_stale(queue_name) -> Hash {waiting: Integer, active: Integer}
      def expire_stale(queue_name)
        now = current_timestamp

        with_ar do
          ActiveRecord::Base.transaction do
            ensure_mutex(queue_name)
            expire_stale_internal(queue_name, now)
          end
        end
      end

      private

      def waiting_entry_key(queue_name, identity)
        "#{KEY_PREFIX}:waiting:#{queue_name}:#{identity}"
      end

      def active_entry_key(queue_name, identity)
        "#{KEY_PREFIX}:active:#{queue_name}:#{identity}"
      end

      def mutex_key(queue_name)
        "#{KEY_PREFIX}:mutex:#{queue_name}"
      end

      def waiting_key_pattern(queue_name)
        "#{KEY_PREFIX}:waiting:#{ActiveRecord::Base.sanitize_sql_like(queue_name)}:%"
      end

      def active_key_pattern(queue_name)
        "#{KEY_PREFIX}:active:#{ActiveRecord::Base.sanitize_sql_like(queue_name)}:%"
      end

      def identity_from_key(key, queue_name)
        key_s = key.to_s
        %w[waiting active].each do |state|
          prefix = "#{KEY_PREFIX}:#{state}:#{queue_name}:"
          return key_s.sub(prefix, "") if key_s.start_with?(prefix)
        end
        key_s
      end

      def current_timestamp
        ::Time.now.to_f
      end

      # Reads and parses a JSON value using Solid Cache's key_hash-based read.
      # Returns nil if the key does not exist.
      def read_value(key)
        raw = ::SolidCache::Entry.read(key)
        return nil unless raw
        parse_value(raw, key: key)
      end

      # Parses a JSON value. On parse failure, includes a hashed key fragment
      # for debugging without leaking PII (L0036).
      def parse_value(value, key: nil)
        JSON.parse(value.to_s)
      rescue JSON::ParserError => e
        if key
          digest = Digest::SHA256.hexdigest(key.to_s)[0, 12]
          raise JSON::ParserError, "#{e.message} [key digest: #{digest}]"
        end
        raise
      end

      # Counts active entries by scanning only the active key prefix.
      # Materializes active rows only (bounded by max_concurrent), not the
      # full queue. Ruby-side JSON parsing for expires_at is unavoidable
      # because Solid Cache's KV schema has no per-entry TTL column.
      def active_count_internal(queue_name, now)
        ::SolidCache::Entry.uncached do
          ::SolidCache::Entry
            .where("key LIKE ?", active_key_pattern(queue_name))
            .count do |entry|
              parse_value(entry.value, key: entry.key)["expires_at"] > now
            end
        end
      end

      # Counts non-expired waiting entries with enqueued_at <= target.
      # Scans only the waiting key prefix; does not touch active rows.
      def waiting_position(queue_name, enqueued_at, now)
        ::SolidCache::Entry.uncached do
          ::SolidCache::Entry
            .where("key LIKE ?", waiting_key_pattern(queue_name))
            .count do |entry|
              value = parse_value(entry.value, key: entry.key)
              value["expires_at"] > now && value["enqueued_at"] <= enqueued_at
            end
        end
      end

      def ensure_mutex(queue_name)
        key = mutex_key(queue_name)
        ::SolidCache::Entry.write(key, "1")
        # Verify the mutex row exists using read (key_hash-based lookup)
        raise Error, "Waitmate Solid Cache mutex acquisition failed" unless ::SolidCache::Entry.read(key)
      end

      # Purges expired entries from both waiting and active prefixes.
      # Called inside the mutex-protected transaction so no concurrent
      # reader sees partially-purged state.
      def expire_stale_internal(queue_name, now)
        waiting_count = 0
        active_count = 0

        ::SolidCache::Entry.uncached do
          ::SolidCache::Entry.where("key LIKE ?", waiting_key_pattern(queue_name)).each do |entry|
            if parse_value(entry.value, key: entry.key)["expires_at"] <= now
              ::SolidCache::Entry.delete_by_key(entry.key)
              waiting_count += 1
            end
          end
        end

        ::SolidCache::Entry.uncached do
          ::SolidCache::Entry.where("key LIKE ?", active_key_pattern(queue_name)).each do |entry|
            if parse_value(entry.value, key: entry.key)["expires_at"] <= now
              ::SolidCache::Entry.delete_by_key(entry.key)
              active_count += 1
            end
          end
        end

        {waiting: waiting_count, active: active_count}
      end

      def with_ar
        yield
      rescue ActiveRecord::ActiveRecordError => e
        raise ConnectionError,
          "Waitmate could not reach Solid Cache (#{e.class}: #{e.message}). " \
          "Verify the database connection."
      rescue JSON::ParserError => e
        raise Error, "Waitmate Solid Cache store corrupted value (#{e.class}: #{e.message})"
      rescue => e
        raise Error, "Waitmate Solid Cache store error (#{e.class}: #{e.message})"
      end
    end
  end
end
