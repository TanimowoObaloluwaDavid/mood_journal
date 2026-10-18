# Changelog

All notable changes to this project are documented here.
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [0.2.0] — 2026-10-18

### Added

- **Web support.** SQLite runs as WebAssembly in a worker, chosen at compile
  time through a conditional export, so there is still only one set of queries
  and one set of models. drift uses OPFS when the page is cross-origin isolated
  and IndexedDB otherwise.
- **Screenshots and a demo video** in the README, captured from the real app via
  headless Chrome over the DevTools Protocol. The tooling lives in `tool/` and
  is committed, so the images can be regenerated.
- **`tool/serve.js`** — a static server that gets `.wasm` MIME types and COOP/COEP
  headers right, which a generic server does not.
- **`DemoSeeder`** — ~11 weeks of plausible sample entries, behind
  `--dart-define=DEMO_DATA=true`. Tree-shaken out of ordinary builds.

### Fixed

- **Deep links above the shell rendered a blank screen.** `/search` and
  `/settings` were declared as `ShellRoute` children with a `parentNavigatorKey`
  that was attached to no Navigator. On a cold load — a pasted URL, or a
  refresh — go_router built a stack that produced nothing. They are now
  siblings of the `ShellRoute`, like the editor routes.
- **Entry rows printed the body twice** when no explicit title was set: the
  derived title and the preview underneath were the same words. Added
  `hasExplicitTitle` to gate the preview, with regression tests.
- **Mood chart axis labels were clipped** at both ends of the x-axis.

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
