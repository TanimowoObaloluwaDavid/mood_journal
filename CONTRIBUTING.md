# Contributing

Thanks for considering a contribution. This document covers setup, the
conventions the codebase follows, and the few places where a change that looks
harmless would quietly break the app.

## Setup

```bash
flutter pub get
dart run build_runner build
flutter test
```

Requires Flutter 3.41+ / Dart 3.11+.

`dart run build_runner build` generates `lib/data/local/app_database.g.dart` from
the drift table definitions. **CI fails if that file is stale**, so if you touch
`lib/data/local/tables.dart`, regenerate it and commit the result.

## Conventions

- **Layering is one-directional.** `presentation → application → domain ← data`.
  Nothing in `lib/domain` may import Flutter or anything from `lib/data`. That
  is what makes the domain testable without a widget tree.
- **Widgets never touch the database.** They read providers. Mutations go through
  `JournalRepository` and then call `invalidateDerived(ref.invalidate)`.
- **No `await` before `runApp` in `main()`.** The cold-start budget is documented
  in `SPEC.md` §7.
- **Comments explain *why*, not *what*.** The codebase is dense with "why" comments
  because most of the non-obvious decisions are load-bearing. Don't add comments
  that restate the code.
- **Run `flutter analyze --fatal-infos` before opening a PR.** It must be clean.

## Things that will break the app if you get them wrong

**Moods are integers 1–5.** Not an enum ordinal, not a string. Charts average
them. Moods as strings would silently corrupt every statistic.

**A day with no entries is `null`, never `0`.** See `DayMood.average`. A zero
pulls averages down and paints blank days red.

**Day bucketing goes through `startOfDay`.** Never `DateTime.now()` for a stored
entry date, and never raw epoch millis in a comparison. `daysBetween` normalises
to UTC so a DST boundary cannot produce a 0.958-day gap.

**Encryption skips values that are already envelopes.** `CryptoService.isEnvelope`
is checked on every write path. Toggling encryption off leaves plaintext rows
behind; toggling it back on must not double-encrypt them. There is a test for
this and it is worth respecting.

**The y-axis on the mood chart is pinned to 1–5.** Do not make it auto-scale; it
turns a small improvement into a dramatic-looking mountain range.

**Semantics on mood controls use a single merged node.** `container: true` and
`excludeSemantics: true` together, with the tap action declared on the `Semantics`
widget itself. Splitting them makes a screen reader focus an unlabelled button.

**`tags` needs both `primaryKey` and `uniqueKeys`.** `entry_tags.tag_id` references
`tags.id`, and SQLite rejects a foreign key whose parent column is not a primary
key. This bug shipped briefly and broke every tagged write.

## Adding a feature

1. Domain model and repository method first, in `lib/domain`.
2. The drift implementation in `lib/data`.
3. A test against an in-memory database in `test/journal_repository_test.dart`.
4. Provider wiring in `lib/presentation/providers.dart`.
5. UI last.

This order exists so you find out whether the data model works before you have
built a screen on top of it.

## Reporting bugs

Open an issue with the Flutter version (`flutter --version`), the platform, and
the smallest set of steps that reproduces it. If data was lost, that is the
priority — say so in the title.

## Pull requests

- One concern per PR.
- Add or update tests for behaviour changes.
- Update `README.md` if you changed the stack or the setup.
- Update the Roadmap in `README.md` if you finished something on it.

## Licence

By contributing you agree that your work is licensed under the [MIT Licence](LICENSE).
