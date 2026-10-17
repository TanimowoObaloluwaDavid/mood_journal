# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [0.1.0] — 2026-10-17

First working build.

### Added

- **Home** — one-tap mood card that persists immediately, streak banner
  (current / longest / days logged), and a timeline of recent entries.
- **Editor** — debounced autosave (800 ms) that also flushes on dispose,
  mood picker, tags, and back-dating.
- **Calendar** — GitHub-style 26-week mood heatmap plus a list of this month's
  entries.
- **Insights** — mood-over-time line chart pinned to 1–5, mood distribution,
  mood-by-weekday, writing statistics, top tags, and a link to the longest entry.
- **Search** — 150 ms debounced full-text search across entry text and tags.
- **Settings** — reminder time, daily prompt, encryption toggle, passcode
  toggle, theme selection, JSON export, a diagnostics log, and erase-all.
- **AES-256-GCM encryption** for entry titles and bodies, with the key stored in
  the platform keystore. Toggling the setting rewrites every row in one
  transaction.
- **Streaks** with the edge cases handled: multiple entries a day count once, a
  one-day gap is forgiven, today being empty doesn't break a streak that ended
  yesterday, and future-dated entries never extend one.
- **Accessibility** — semantic labels and merged tap targets on every mood
  control, mood never conveyed by colour alone, 48×48 touch targets.
- **Diagnostics** — the last 100 unhandled errors, viewable from Settings.

### Engineering

- Riverpod for state, `go_router` for navigation, Drift/SQLite for storage.
- Strict one-directional layering; `lib/domain` has no Flutter dependency.
- 58 tests covering streak maths, DST-aware day bucketing, the full repository
  surface, the encryption round-trip, and widget semantics.
- CI runs analyze, tests, a stale-codegen check, and a debug APK build.

### Known limitations

- Notifications are configured but not scheduled.
- The passcode setting persists; the lock screen is not built.
- Export only; there is no import.
- Verified on Android only.
