<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/waitmate_logo_dark.svg">
    <source media="(prefers-color-scheme: light)" srcset=".github/waitmate_logo_light.svg">
    <img alt="Waitmate" src=".github/waitmate_logo_light.svg" width="220">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/bart-oz/waitmate/releases"><img src="https://img.shields.io/badge/version-0.1.0-blue.svg" alt="Version"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License"></a>
  <a href="https://github.com/bart-oz/waitmate/actions"><img src="https://img.shields.io/badge/tests-passing-brightgreen.svg" alt="Tests"></a>
  <a href="https://github.com/bart-oz/waitmate/actions"><img src="https://img.shields.io/badge/coverage-96.36%25-brightgreen.svg" alt="Coverage"></a>
</p>

---

Virtual waiting room for Rails applications.

Waitmate protects expensive controller actions from thundering-herd overload by queuing overflow users, issuing encrypted admission tickets, and letting users wait on a lightweight Engine-provided page.

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

Run the install generator to create an initializer:

```bash
rails generate waitmate:install
```

This copies `config/initializers/waitmate.rb` with the current defaults.

## Configuration

All config keys and their defaults:

```ruby
Waitmate.configure do |config|
  config.adapter = :redis              # :redis or :solid_cache
  config.queue_ttl = 300             # seconds before abandoned queue entries expire
  config.polling_interval = 5        # seconds between queue status polls
  config.ticket_ttl = 120            # seconds before admission tickets expire
  config.waiting_room_path = "/waitmate/room" # Engine path for the waiting-room page
end
```

- `adapter` — Storage backend. `:redis` is primary; `:solid_cache` is the SQL fallback.
- `queue_ttl` — Time-to-live for a queue entry. Each successful poll extends the TTL.
- `polling_interval` — How often the browser asks for its position.
- `ticket_ttl` — How long an issued admission ticket remains valid.
- `waiting_room_path` — The URL the waiting-room controller renders. Must match the `mount` path in the host routes plus the engine's `/room` route.

### Choosing an adapter

- **Redis (`:redis`)** — Best for high-traffic or latency-sensitive rooms. Each poll is roughly O(1) for the requesting user.
- **Solid Cache (`:solid_cache`)** — Best when you want a Rails/Solid Stack setup without running Redis. It keeps the same queue correctness contract, but throughput depends on your database. Each poll materializes the waiting rows for that queue to compute a position, so it becomes the throughput bottleneck for large or long queues.

For Solid Cache, install and migrate Solid Cache first, then set `config.adapter = :solid_cache`. Use Redis when you need the highest concurrency; use Solid Cache when simpler Rails-only operations matter more.

## Usage

```ruby
class TicketsController < ApplicationController
  wait_room :purchase, max_concurrent: 100
end
```

### Waiting-room flow

1. The first request to a protected action is enqueued. If capacity is available, the action runs immediately.
2. When the action is at capacity, Waitmate issues an encrypted ticket and redirects the browser to the Engine waiting room (`/waitmate/room` by default, controlled by `config.waiting_room_path`).
3. The waiting room verifies the ticket against the user's session and queue, then polls the `/waitmate/room/position` endpoint every `polling_interval` seconds (default 5). Each poll extends the queue entry's TTL.
4. When the user's position reaches 0, the waiting room redirects back to the original target URL with the ticket. The concern re-verifies the ticket and admits the user.
5. Invalid tickets or unsafe targets show a generic, safe error page with no raw tickets, session IDs, queue internals, or adapter errors.

Tickets expire after `ticket_ttl` seconds (default 120). If a user waits longer than the ticket TTL without a successful poll, the ticket becomes invalid and the waiting room shows the generic error page; the user must refresh or re-enter the protected action to obtain a new ticket.

### Overriding the waiting-room view

Hosts can replace the default waiting-room page by creating:

```
app/views/waitmate/rooms/show.html.erb
```

The controller sets the following instance variables:

- `@position` — the user's current queue position (`0` means admitted; `nil` on the error path).
- `@polling_interval` — value of `config.polling_interval`.
- `@ticket` — the encrypted ticket string.
- `@queue` — the queue name.
- `@target` — the validated target URL to return to after admission.
- `@error` — `true` on the invalid-ticket / unsafe-target path, otherwise unset.

On the normal waiting path, all of the above except `@error` are present. On the error path, only `@error`, `@position` (nil), and `@polling_interval` are guaranteed. Override templates must not assume `@ticket`, `@queue`, or `@target` exist when `@error` is truthy.

### Polling interval and Solid Cache caveat

`polling_interval` controls how often the browser asks for its queue position. Lower intervals feel more responsive but generate more requests.

The Redis adapter answers each poll in roughly O(1) time for the requesting user. The Solid Cache adapter, by design, must scan and rank waiting rows to compute a position, so each poll materializes the waiting rows for that queue. This is acceptable for moderate traffic but becomes the throughput bottleneck for large or long queues. Use Redis when polling latency and queue depth matter.

## Limitations (v0.1)

- **Transport:** HTTP polling only. ActionCable/Turbo Streams are deferred to a future release.
- **Integration:** Controller concern only. No Rack middleware.
- **Storage:** Redis and Solid Cache only. No additional adapters.
- **Framework:** Rails-only. No standalone Rack or non-Rails support.
- **UI:** A single, overridable ERB waiting-room page. No admin dashboard, CAPTCHA, or anti-bot functionality.

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bin/quality` to run the full gate suite: RSpec, StandardRB, appraisal runs against Rails 7.1/7.2/8.0, and `bundler-audit`.

Use `bin/quality --skip-appraisal` for a fast inner-loop check that skips the Rails-version matrix.

## License

Released under the MIT License.
