# Mood Journal — Detailed Product & Technical Specification

> App idea #9 from the Flutter app-ideas list: **Journal with mood tracking**
> Daily entry + mood emoji picker, streaks, mood-over-time charts, encrypted local storage.

---

## 1. Product Definition

### 1.1 One-line pitch
A private, offline-first journal where you log how you feel in 5 seconds, and the app
turns a year of those taps into insight: streaks, trends, word counts, and correlations.

### 1.2 Target user
Someone who already tried journaling and quit because it was "too much writing".
The core interaction is **one tap on an emoji**, not a blank page.

### 1.3 Non-goals (v1)
| Out of scope | Why |
|---|---|
| Cloud sync / accounts | Local-first is a feature, not a limitation. Sync is v2 via Supabase. |
| AI sentiment analysis | Requires network + cost. v2. |
| Social feed / sharing | Undermines the privacy promise. |
| Photos in entries | v1.1 (schema already reserved, see §5.2) |

### 1.4 Success criteria
- Time from app open → entry saved: **< 8 seconds** (median).
- App is fully usable with airplane mode on.
- No entry text ever leaves the device unencrypted.
- Zero crashes on a 5-year-old mid-range Android device.

---

## 2. Feature Specification

### 2.1 Home / Today

```
┌──────────────────────────────────┐
│  Saturday, 17 October      🔒  ⚙ │
│                                   │
│   ╭───────────────────────────╮  │
│   │  How are you feeling?     │  │
│   │                           │  │
│   │   😄  🙂  😐  😟  😢       │  │  ← 5 moods, 1 tap
│   │    5   4   3   2   1       │  │
│   ╰───────────────────────────╯  │
│                                   │
│   🔥 12 day streak                │
│                                   │
│   ── Recent entries ──            │
│   │ Fri · 🙂 · "Shipped the..."  │ │
│   │ Thu · 😄 · "Great call..."   │ │
│   │ Tue · 😐 · (no text)         │ │
└──────────────────────────────────┘
```

**Behaviours**
- `F2 Today card` — tapping an emoji **immediately persists** a mood row (no save button).
- If today already has a mood, the card renders in "edit" mode: the selected emoji is
  filled, and the written text (if any) is shown inline with a **Keep writing** action.
- Tapping a *different* emoji than today's just updates it in place.
- `F3 Streak header` — current streak, longest streak, and total days logged.
- `F4 Recent list` — up to 30 entries, newest day first, each row tappable (`/entry/:id`).
- `F5 FAB` — "New entry" for back-dating / multiple entries a day.
- `F6 Pull to refresh` — re-reads from DB (mostly a no-op, but guarantees consistency
  after coming back from the background).

**States**
| State | Trigger | UI |
|---|---|---|
| Empty | No entries ever | Emoji card + "Your journal starts here" |
| Mood only | Mood saved, no text | Card stays in edit mode with an "Add some words" action |
| Complete | Mood + text saved | Card shows filled emoji, preview text, and "Keep writing" |
| Error | DB read throws | Full-screen error with **Retry**; never a blank screen |


### 2.2 Entry Editor (`/entry/:id`)

- Text field, `maxLines: null`, autofocus on create.
- **Mood picker** — 5 options, each with emoji + label + colour token.
- **Tags** — free-form, comma-separated; existing tags offered as chips.
- **Prompt** — one optional line ("What went well today?") stored on the entry record so
  the UI can rotate prompts deterministically per day.
- **Time** — defaults to now; editable to back-date.
- Autosave: debounced 800 ms after the last keystroke → persists without a Save button.
- Delete in overflow menu, with a confirm dialog.

### 2.3 Calendar (`/calendar`)

GitHub-style contribution heatmap, last 26 weeks (182 days).
- Cell colour = average mood that day, 5 buckets.
- Empty day = hairline outline. Future days = hidden.
- Tap a day → jumps to that day's entry, or to the editor if none exists.

### 2.4 Insights (`/insights`)

1. **Mood line chart** — `fl_chart` LineChart, 30-day rolling average + per-day dots.
2. **Mood distribution** — bar chart, days per mood bucket.
3. **Mood by weekday** — grouped bars, reveals "Sundays are my worst day".
4. **Streak stats** — current, longest, total days, this-month count.
5. **Writing stats** — total words, average words/entry, entries per week (last 8).
6. **Top tags** — top 8 by frequency, as a wrap of chips.
7. **Longest entry** — a teaser card that links to it.

All charts read from a **single aggregated query**, not N queries over rows.

### 2.5 Search (`/search`)

- Single text field, results as you type (150 ms debounce).
- Matches entry **title**, **body**, and **tags** (LIKE `%q%`).
- Empty state explains what is searchable.

### 2.6 Settings (`/settings`)

| Setting | Type | Default | Notes |
|---|---|---|---|
| Reminder time | Time picker | 21:00 | Scheduled locally |
| Reminders on/off | Switch | `true` | |
| Daily prompt on/off | Switch | `true` | Prompt rotates deterministically per day |
| Encrypt entries | Switch | `true` | Turning off decrypts every row in one transaction |
| Passcode lock | Switch | off | Setting persisted; the lock screen is v1.1 |
| Theme | Segmented | `system` | light / dark / system |
| Export JSON | Button | — | Copies every entry to the clipboard |
| Diagnostics | List tile | — | Last 100 unhandled errors, monospace |
| Danger zone | Button | — | "Erase all entries" + confirm dialog |

Export uses the clipboard rather than `share_plus`: it keeps the app fully
offline and avoids a native dependency for one button.


---

## 3. Data Model

### 3.1 Entity relationship
```
mood_tags ────┐
journal_entries┼──< entry_tags >── tags
app_settings ─┘
```

### 3.2 `journal_entries`
| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | `Uuid.v4()` generated client-side |
| `title` | TEXT | nullable; **encrypted**. Falls back to first 6 words of body |
| `body` | TEXT | **encrypted** |
| `prompt` | TEXT | nullable. Left plaintext: app-authored, not user content |
| `entry_date` | INTEGER | drift `dateTime()`, midnight local — the day bucket |
| `mood` | INTEGER | 1–5, nullable |
| `energy` | INTEGER | 1–5, nullable (v1.1 field, UI hidden) |
| `word_count` | INTEGER | denormalised, written on save so totals are a SUM |
| `is_favorite` | INTEGER | 0/1 |
| `created_at` | INTEGER | drift `dateTime()` |
| `updated_at` | INTEGER | drift `dateTime()` |

Dates use drift's `dateTime()` rather than raw epoch millis. drift stores unix
**seconds** and converts on read, so DST and timezone changes cannot corrupt a
day bucket — and `_moodByWeekday` can use `'unixepoch','localtime'` in SQL.

**Indexes:** `idx_entries_date (entry_date DESC)`, `idx_entries_updated (updated_at DESC)`,
created in `onCreate` alongside `migrate.createAll()`.


### 3.3 `mood_tags` (sub-moods — v1.1)
Per-entry secondary feelings, so "😄 + anxious" is expressible.
`id`, `entry_id` (FK → `journal_entries`, CASCADE), `mood_id`, `created_at`.

### 3.4 `tags` / `entry_tags`
`tags(id, name UNIQUE)` · `entry_tags(entry_id, tag_id)` with a composite PK and
`ON DELETE CASCADE` on both foreign keys.

### 3.5 `app_settings`
Single key/value row holding the whole `AppSettings` object as JSON, so adding a
preference never requires a migration. `key TEXT PK`, `value TEXT`, `updated_at`.

### 3.6 Migration policy
- Schema version lives in drift's `schemaVersion`.
- `MigrationStrategy.onCreate` creates tables and indexes together.
- Migrations are append-only. Never edit a shipped migration.
- `beforeOpen` enables `PRAGMA foreign_keys = ON`, without which the tag
  cascade silently does nothing.


---

## 4. Architecture

### 4.1 Layering (strict, one-directional dependencies)
```
presentation  ──▶  application  ──▶  domain  ◀──  data
   (widgets)        (providers)     (models)     (db, repo)
```
`domain` imports **nothing** from the other layers. `data` implements `domain` interfaces.

### 4.2 State management — Riverpod

| Provider | Type | Purpose |
|---|---|---|
| `appDatabaseProvider` | `Provider` | single Drift instance |
| `cryptoServiceProvider` | `Provider` | AES-GCM + keystore |
| `settingsRepositoryProvider` | `Provider` | settings persistence |
| `journalRepositoryProvider` | `Provider` | repository |
| `errorLogProvider` | `Provider` | last 100 errors, overridden in `main` |
| `appSettingsProvider` | `AsyncNotifierProvider` | settings, bootstrapped at startup |
| `entriesProvider` | `AsyncNotifierProvider<List<JournalEntry>>` | timeline |
| `entryProvider(id)` | `FutureProvider.autoDispose.family` | one entry |
| `todayEntryProvider` | `FutureProvider` | today's bucket |
| `streakProvider` | `FutureProvider` | current + longest |
| `heatmapProvider` | `FutureProvider<List<DayMood>>` | 26 weeks |
| `insightsProvider` | `FutureProvider<InsightsBundle>` | every chart's data |
| `entryCountsProvider` | `FutureProvider<int>` | total count |
| `searchQueryProvider` | `Notifier<String>` | debounced in the widget |
| `searchResultsProvider` | `FutureProvider.autoDispose.family` | query → entries |
| `allTagsProvider` | `FutureProvider<List<String>>` | tag chips |
| `dailyPromptProvider` | `Provider<String>` | deterministic prompt for today |
| `todayDraftProvider` | `Notifier<TodayDraft>` | in-progress buffer |
| `uuidProvider` | `Provider<String Function()>` | client-side ids |

Rules enforced in the codebase:
- Widgets never touch the database. They only read providers.
- Mutations go through repository methods, then call `invalidateDerived`.
- Every provider exposes an explicit `AsyncValue` so loading and error are handled.
- `invalidateDerived` takes `ref.invalidate` as a callback, not a `Ref`, because in
  Riverpod 2.x a `WidgetRef` is not a `Ref` and mutations originate from both.

### 4.3 Navigation — `go_router`
| Route | Screen |
|---|---|
| `/` | Home |
| `/entry/new?id=&date=` | Editor (id minted by the caller) |
| `/entry/:id` | Editor |
| `/calendar` | Calendar |
| `/insights` | Insights |
| `/search` | Search |
| `/settings` | Settings |

`ShellRoute` gives the three tabs a persistent `NavigationBar` with state preserved.
Search, Settings and the Editor sit outside the shell so they get the full screen
and a back button.


### 4.4 Error handling
- `Result<T>` — no exceptions cross a layer boundary.
- `AppException` with a user-facing `message`.
- Global `FlutterError.onError` + `PlatformDispatcher.instance.onError` → log to
  a ring buffer of 100 entries, exposed on a hidden Settings → Diagnostics screen.

---

## 5. Mood Model

### 5.1 The five moods
| Value | Emoji | Label | Colour token |
|---|---|---|---|
| 5 | 😄 | Great | `mood5` (green) |
| 4 | 🙂 | Good | `mood4` (teal) |
| 3 | 😐 | Okay | `mood3` (amber) |
| 2 | 😟 | Low | `mood2` (orange) |
| 1 | 😢 | Bad | `mood1` (red) |

Arithmetic mean is meaningful here, so moods are stored as **ints**, never as strings.

### 5.2 Average mood for a day
`AVG(mood)` over all entries for that day, rounded. Multiple entries a day average out.
Days with no entries are `null`, never `0` — a `0` would corrupt every average.

---

## 6. Encryption

Threat model: someone gets the device unlocked and opens the app's data directory, or
reads a stolen phone's storage over USB.

- Cipher: **AES-256-GCM** via `package:cryptography`.
- Key: 32 random bytes, generated once, stored in the platform keystore/keychain via
  `flutter_secure_storage`.
- Envelope: `v1:<base64(nonce)>:<base64(mac)>:<base64(ciphertext)>`.
- Only `body` and `title` are encrypted. Dates and moods stay plaintext so that
  aggregations and heatmaps work in SQL without decrypting every row.
- Key loss ⇒ unrecoverable data. Settings shows a permanent warning that there is no
  cloud backup before the user relies on encryption.
- Toggling the setting rewrites **every** row in one transaction, decrypting or
  encrypting as needed. `_protect` skips values that are already envelopes, so a
  toggle can never double-encrypt.

### 6.1 The search trade-off
Because `body` is ciphertext, `LIKE '%q%'` can never match. Search is therefore
decrypt-and-filter in memory, capped at the 2 000 most recent rows with 50 results
returned. That is the honest trade: a journal is thousands of rows, not millions,
and the alternative (a plaintext index) would undo the encryption entirely.


---

## 7. Performance Budgets

| Screen | Budget | Technique |
|---|---|---|
| Home cold start | < 400 ms | Drift lazy-open, no `await` before `runApp` |
| Timeline scroll | 60 fps at 2 000 entries | `ListView.builder`, fixed-height rows |
| Calendar heatmap | < 80 ms | one grouped query → 182 in-memory buckets |
| Insights | < 200 ms | single aggregate query, no per-row decrypt |
| Search | < 50 ms | `LIKE` on indexed columns, 150 ms debounce |

---

## 8. Accessibility

- Every emoji control has a `Semantics(label:)` — screen readers say "Mood: Good",
  not "smiling face with smiling eyes".
- Mood is never conveyed by colour alone; the emoji and label carry the meaning
  (this is a WCAG 1.4.1 requirement, not a nice-to-have).
- Minimum touch target 48×48.
- Text scales to 200 % without overflow.
- `respectReducedMotion` disables chart animations.

---

## 9. Testing Strategy

| Layer | What is tested | Count |
|---|---|---|
| Unit | streak math, DST-aware day bucketing, word count, mood mapping | 21 |
| DAO/repository | every query against an in-memory `NativeDatabase`, including the encryption round-trip | 30 |
| Widget | mood picker rendering, tap targets, and screen-reader labels | 7 |

**`test/streak_test.dart`** — the streak edge cases from §5, plus `daysBetween` across
a DST boundary and whitespace word counting.

**`test/journal_repository_test.dart`** — create → read → edit → delete, ciphertext
actually landing on disk, distinct nonces for identical plaintext, encrypt→decrypt→
encrypt without double-encrypting, case-insensitive tag dedupe, same-day ordering,
heatmap `null` vs `0` averages, and word-total aggregation.

**`test/mood_picker_test.dart`** — all five moods render, taps report the right mood,
the selected state is exposed as a semantics flag, and the widget survives a theme
with no palette registered.

Streak edge cases that must be covered by unit tests — all implemented:
1. Streak of 1 today, nothing yesterday → `1`.
2. Gap of exactly 1 day preserves the streak; 2 days resets it.
3. Multiple entries a day count once.
4. A future-dated entry never extends a streak.
5. No entries at all → `0`, not `null`.
6. Today empty but yesterday present → streak still alive.

### 9.1 Bugs these tests caught
Worth recording, because each one was invisible to the analyzer:

- **`tags` had no PRIMARY KEY.** `uniqueKeys` was declared but `primaryKey` was not,
  so SQLite rejected every write to `entry_tags` with a foreign-key mismatch. The
  app would have crashed on the first tagged entry.
- **`getEntryById` never loaded tags.** Only the list query hydrated them, so opening
  a single entry showed no tags and an edit would silently delete them all.
- **`toggleFavorite` returned the pre-update row**, so every favourite tap appeared
  to do nothing.
- **Same-day ordering was nondeterministic** on timestamp ties, which could show the
  wrong mood on the home screen. Fixed with a `rowid DESC` tiebreaker.
- **`MoodPalette` was force-unwrapped** (`Theme.of(context).extension<...>()!`), so any
  screen rendered without the app theme crashed. Now falls back by brightness.


---

## 10. Build Order

1. `flutter create`, `pubspec.yaml`, theme, colour tokens
2. Drift schema + indexes + migration strategy
3. Domain models (`JournalEntry`, `Mood`, `DayMood`, `StreakStats`, `InsightsBundle`)
4. Repository interface in `domain/`, Drift implementation in `data/`
5. Settings + key storage + `CryptoService`
6. `go_router` + `ShellRoute`
7. Home screen (the 8-second flow)
8. Editor with debounced autosave
9. Calendar heatmap
10. Insights + `fl_chart`
11. Search
12. Settings, export, diagnostics, erase
13. Tests + a11y pass

### 10.1 Deliberate deviations
| Spec said | Built instead | Why |
|---|---|---|
| `drift_flutter` | `drift/native.dart` | `drift_flutter` pins `sqlite3 ^2.4.6` while current drift needs `^3.4.0`; the two can never resolve together |
| Epoch-millisecond integers | drift `dateTime()` columns | drift handles seconds/UTC conversion, which removes a whole class of DST bug |
| Local notifications | Setting persisted, scheduling is v1.1 | `flutter_local_notifications` adds a plugin surface for a feature that needs real device testing |
| Import JSON | Export only | Import needs conflict-merge policy and a migration story before it is safe |


---

## 11. Definition of Done

- [x] `flutter analyze` — no issues
- [x] `flutter test` — 58 passing
- [x] `flutter build apk --debug` — succeeds
- [x] All 6 streak edge-case unit tests pass
- [x] Ciphertext verified on disk; identical plaintext produces distinct nonces
- [x] Encryption toggle round-trips without double-encrypting
- [x] Screen-reader labels on every mood control
- [ ] Works with the network fully disabled — *manual, airplane mode on device*
- [ ] 2 000 seeded entries scroll at 60 fps — *needs a physical device*
- [ ] Full screen-reader walkthrough — *needs a real device*
- [ ] Local notification scheduling — *v1.1, setting is persisted only*

