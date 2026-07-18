# Changelog

All notable changes to this project will be documented in this file.

## [0.2.0] — Turbo Drive Compatibility

### Added

- Turbo Drive-compatible redirects: all Waitmate redirects now emit `303 See Other` (`redirect_to ..., status: :see_other`), which Turbo Drive recognizes as a full-page navigation trigger.
- `<meta name="turbo-visit-control" content="reload">` in the waiting-room page `<head>` to break out of Turbo Drive/Frame rendering.

### Fixed

- Waiting room page invisible under Turbo Drive: Turbo Drive followed `302` redirects and treated the full-document room HTML as a Turbo Stream update, discarding it. `303` forces a standard navigation.

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

- HTTP polling only; ActionCable/Turbo Streams *push delivery* (server-initiated streams) is deferred to a future release. Turbo Drive redirect compatibility is supported since v0.2.0.
- Controller-concern integration only; no Rack middleware.
- Redis and Solid Cache are the only supported storage adapters.
- Rails-only; no standalone Rack or non-Rails support.
- Single waiting-room page; no admin dashboard, CAPTCHA, or anti-bot functionality.
