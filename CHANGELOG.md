# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - Released 2026-06-13

### Added

- Isolated Rails Engine mounted with `mount Waitmate::Engine => "/waitmate"`.
- `wait_room :action, max_concurrent: N` controller concern for gating expensive actions.
- Encrypted admission tickets via `ActiveSupport::MessageEncryptor`, bound to queue, expiry, and session identity.
- Redis primary storage adapter with atomic Lua-based enqueue, admit, release, and position operations.
- Solid Cache SQL fallback adapter using `SolidCache::Entry`.
- HTTP-polling waiting-room page at `/waitmate/room`, with a `/waitmate/room/position` endpoint that doubles as a heartbeat.
- Configurable `adapter`, `queue_ttl`, `polling_interval`, `ticket_ttl`, and `waiting_room_path`.
- Host-app override of the waiting-room view via `app/views/waitmate/rooms/show.html.erb`.
- `rails generate waitmate:install` generator that copies `config/initializers/waitmate.rb`.
- RSpec test suite, StandardRB linting, and `bundler-audit` security gate run by `bin/quality`.

### Limitations

- HTTP polling only; ActionCable/Turbo Streams are not implemented.
- Controller-concern integration only; no Rack middleware.
- Redis and Solid Cache are the only supported storage adapters.
- Rails-only; no standalone Rack or non-Rails support.
- Single waiting-room page; no admin dashboard, CAPTCHA, or anti-bot functionality.
