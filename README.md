# Waitmate

Virtual waiting room for Rails applications.

Waitmate protects expensive controller actions from thundering-herd overload by queuing overflow users, issuing signed admission tickets, and letting users wait on a lightweight Engine-provided page.

## Installation

Add to your Gemfile:

```ruby
gem "waitmate"
```

And then execute:

```bash
bundle install
```

Mount the engine in your routes:

```ruby
mount Waitmate::Engine => "/waitmate"
```

## Configuration

```ruby
Waitmate.configure do |config|
  config.adapter = :redis          # or :solid_cache
  config.queue_ttl = 300           # seconds before abandoned queue entries expire
  config.polling_interval = 5      # seconds between queue status polls
  config.ticket_ttl = 120          # seconds before admission tickets expire
end
```

### Choosing an adapter

- **Redis (`:redis`)** — Best for high-traffic or latency-sensitive rooms.
- **Solid Cache (`:solid_cache`)** — Best when you want a Rails/Solid Stack setup without running Redis. It keeps the same queue correctness contract, but throughput depends on your database.

For Solid Cache, install and migrate Solid Cache first, then set `config.adapter = :solid_cache`. Use Redis when you need the highest concurrency; use Solid Cache when simpler Rails-only operations matter more.

## Usage

```ruby
class TicketsController < ApplicationController
  wait_room :purchase, max_concurrent: 100
end
```

### Waiting-room flow

1. The first request to a protected action is enqueued. If capacity is available, the action runs immediately.
2. When the action is at capacity, Waitmate issues an encrypted ticket and redirects the browser to the Engine waiting room (`/waitmate/room` by default).
3. The waiting room verifies the ticket against the user's session and queue, then polls the `/waitmate/room/position` endpoint every `polling_interval` seconds (default 5). Each poll extends the queue entry's TTL.
4. When the user's position reaches 0, the waiting room redirects back to the original target URL with the ticket. The concern re-verifies the ticket and admits the user.
5. Invalid tickets or unsafe targets show a generic, safe error page with no raw tickets, session IDs, queue internals, or adapter errors.

Tickets expire after `ticket_ttl` seconds (default 120). If a user waits longer than the ticket TTL without a successful poll, the ticket becomes invalid and the waiting room shows the generic error page; the user must refresh or re-enter the protected action to obtain a new ticket.

### Overriding the waiting-room view

Hosts can replace the default waiting-room page by creating:

```
app/views/waitmate/rooms/show.html.erb
```

The override must keep the same controller instance variables (`@position`, `@polling_interval`, `@ticket`, `@queue`, `@target`) if it wants to reuse the polling behavior.

### Polling interval and Solid Cache caveat

`polling_interval` controls how often the browser asks for its queue position. Lower intervals feel more responsive but generate more requests.

The Redis adapter answers each poll in roughly O(1) time for the requesting user. The Solid Cache adapter, by design, must scan and rank waiting rows to compute a position, so each poll materializes the waiting rows for that queue. This is acceptable for moderate traffic but becomes the throughput bottleneck for large or long queues. Use Redis when polling latency and queue depth matter.

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bin/quality` to run the test suite, linter, and security audit.

## License

Released under the MIT License.
