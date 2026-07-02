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

## Development

After checking out the repo, run `bundle install` to install dependencies. Then, run `bin/quality` to run the test suite, linter, and security audit.

## License

Released under the MIT License.
