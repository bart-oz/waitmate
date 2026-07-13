# frozen_string_literal: true

Waitmate.configure do |config|
  # Storage adapter. :redis is recommended for high-traffic rooms.
  # :solid_cache is supported when you want a Rails/Solid Stack setup
  # without running Redis. Install and migrate Solid Cache first.
  config.adapter = :redis

  # Seconds before an abandoned queue entry expires. Each poll extends TTL.
  config.queue_ttl = 300

  # Seconds between browser polls for queue position.
  config.polling_interval = 5

  # Seconds before an admission ticket expires.
  config.ticket_ttl = 120

  # Engine path for the waiting-room page. The host app must mount
  # Waitmate::Engine at the matching prefix in config/routes.rb.
  config.waiting_room_path = "/waitmate/room"
end
