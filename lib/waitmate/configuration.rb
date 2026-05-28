# frozen_string_literal: true

module Waitmate
  class Configuration
    attr_accessor :adapter, :queue_ttl, :polling_interval, :ticket_ttl

    def initialize
      @adapter = :redis
      @queue_ttl = 300
      @polling_interval = 5
      @ticket_ttl = 120
    end
  end
end
