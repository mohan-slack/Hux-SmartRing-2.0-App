# HUX App — Foundation

The first bricks of the HUX Flutter app (Track 2). Everything here follows
the rules in the Confluence space **HUX 2.0 Planning** — read pages 1, 3,
5, 6 there before writing code.

## What exists so far

```
lib/core/ring/
  ring_models.dart        The data contract. What "ring data" means in HUX.
  ring_adapter.dart       The wall. The one interface the app talks to.
  mock_ring_adapter.dart  A fake TM21. Realistic data, realistic failures.
```

## The one rule that matters

The app talks to `RingAdapter`. Never to a vendor SDK. Never to a platform
channel directly. When eIoT finally hands over their SDK, we write
`EIoTRingAdapter implements RingAdapter` as a Flutter plugin (Kotlin +
Swift underneath) and swap it in. Nothing above the adapter changes.

If a screen works on the mock but breaks on the real ring, the adapter
implementation is wrong — not the screen.

## Why the mock behaves badly on purpose

The real ring will miss readings, drop connections, and take longer to
sync after long gaps. The mock does all of these (see `chaosMode`).
Building against a polite mock produces an app that falls apart on
real hardware. Build against the rude one.

## Quick start

```dart
final ring = MockRingAdapter(chaosMode: true, seed: 42);

ring.connectionState.listen((s) => print('state: $s'));

final info = await ring.connect();
print('Connected: ${info.name}, battery ${info.batteryPercent}%');

// Catch-up sync: last 24 hours
final result = await ring.syncSince(
  DateTime.now().subtract(const Duration(hours: 24)),
);
print('${result.snapshots.length} snapshots, '
      '${result.sleepSessions.length} nights');

final night = result.sleepSessions.last;
print('Slept ${night.totalSleep.inMinutes} min, '
      'deep ${night.stageTotal(SleepStage.deep).inMinutes} min');
```

## What exists now

```
lib/core/ring/       Data models, adapter interface, mock TM21
lib/core/storage/    HealthStore interface + SQLite implementation
lib/core/sync/       SyncService: overlap, retry, watermark
lib/core/meaning/    Meaning/Action engine: baseline, scoring, readout,
                     Desi Plate action content, Weekly Body Story
lib/core/trends/     Pure per-night chart data (gaps, personal band)
lib/core/modes/      Mode machinery: Big Day, Shaadi, Exam Season
lib/screens/         Today, Trends, Story, Modes — one tabbed app shell
lib/app.dart         HuxApp: MaterialApp + object-graph injection
lib/main.dart        Composition root — the one eIoT swap point
test/                Contract tests for all of the above
```

Storage guarantees (enforced by schema + tests, not by discipline):
- Idempotent writes: timestamp is the PRIMARY KEY, duplicates cannot exist
- Watermark advances only AFTER a successful save: crashes cause
  re-fetch, never gaps
- Every sync re-fetches a 1h overlap window on purpose; the store
  makes it harmless
- deleteAllData() wipes everything: the DPDP "delete my data" hook

The Meaning/Action engine (`lib/core/meaning/`) turns numbers into a
daily readout — the product, not a dashboard:
- `baseline.dart` — `PersonalBaseline`: medians (not means) of the
  user's own last-14-days HRV, resting HR, sleep duration, and skin
  temperature. Fewer than 3 days of history is `insufficient` — the
  engine won't guess at a body it doesn't know yet.
- `daily_readout.dart` — the output model: a `RecoveryState`
  (recharged/steady/stretched/rundown/learning), a headline, a plain-
  English "why" tied to the user's own numbers, 1-2 concrete actions,
  and a `DataQuality` marker for how much of last night's data existed.
- `meaning_engine.dart` — **pure Dart, zero Flutter/storage imports.**
  Scores HRV, sleep duration (+ a deep-sleep floor), resting HR, and
  skin temperature, each *relative to the user's own baseline*, never
  a population norm. Thresholds and weights are named constants with
  tuning comments. Deterministic: same inputs, same readout, always.
  Missing readings are skipped, never guessed at.
- `readout_service.dart` — the only file allowed to touch `HealthStore`;
  loads history, builds the baseline, and calls the engine.

Wellness-only wording is enforced by construction, not convention: the
worst-case language anywhere in a readout is "your body is working
harder than usual" — no diagnoses, no disease names, no alarm.

Two more pieces of insight sit on top of the daily readout, same rules
throughout (personal baseline, never population; wellness wording only;
vegetarian-first Indian register where food comes up):

- **Desi Plate** (`lib/core/meaning/content/action_content.dart`) — the
  action-text library. ~40 concrete, doable-today suggestions keyed by
  (recovery state × dominant signal), picked deterministically from
  `date.day` so the same day always reads the same but the next day
  varies. Still pure Dart; `MeaningEngine` is the only consumer.
- **Weekly Body Story** (`lib/core/meaning/weekly_story.dart`) —
  `WeeklyStoryService` compares the last 7 days against the 7 before
  (sleep, HRV, resting HR, active days) and turns the deltas into a
  handful of plain sentences plus one suggestion for next week. Says so
  honestly, with fewer claims, when either week has fewer than 5
  nights logged.

`lib/core/trends/night_row.dart` is the pure data layer behind the
Trends screen: one row per calendar night (missing nights stay in the
list with null fields, so the UI renders a gap, never a zero), plus the
personal sleep-duration target band (baseline median ± 10%).

The four screens (`lib/screens/`) live under one bottom-navigation
shell (`app_shell.dart`) with an unmissable amber "DEMO — simulated
ring data" banner pinned above all of them — screenshots of this build
must never be mistaken for a real ring. Each tab's state survives
switching away and back (`IndexedStack`, not a rebuilding `TabView`).

**Modes** (`lib/core/modes/`) are HUX's differentiation: the same
Meaning engine, re-aimed at a life moment — a target date, phased
coaching leading up to it, and a readiness message on the day itself.
One mechanic, three themes so far (Big Day, Shaadi, Exam Season); Night
Shift and Fasting are a later phase built on the same machinery.
- `mode.dart` — the model. `ModeId` + `EventModeConfig` (a mode, aimed
  at a target date, with an optional label). At most ONE event mode is
  active at a time — starting a new one replaces the old, with a UI
  confirmation. Persisted via three new `HealthStore` methods
  (`saveModeState`/`loadModeState`/`clearModeState`) backed by a new
  `mode_state` table — schema v1→v2, an additive migration (old
  snapshots/sessions/watermark data is untouched; see the migration
  test in `sqlite_health_store_test.dart`).
- `event_mode_engine.dart` — **pure Dart.** Modes DECORATE a readout
  `MeaningEngine` already computed; this file never rescoring
  anything. Turns days-to-go into a phase (Foundation >21d, Build
  8-21d, Taper 2-7d, Eve 1d, The day 0d, then a one-time "how it went"
  wrap-up once the date has passed) and pulls the phase's themed
  action from the content pack. "Days to go" compares calendar dates
  in the device's LOCAL timezone on purpose — `targetDate` round-trips
  through storage as UTC (this app's usual convention), and comparing
  in UTC directly can land on the wrong calendar day by the user's own
  clock (e.g. IST is UTC+5:30).
- `content/event_content.dart` — the three themes' copy, same
  determinism/forbidden-words rules as Desi Plate. Big Day is neutral
  ("your presentation/interview/match"); Exam Season is UPSC/CA
  register (study blocks, "an hour of sleep beats a 4am cram", exam-eve
  logistics); Shaadi is warm and NEVER appearance-based — coach energy
  and calm, never "look slimmer/better" or weight talk. All three are
  additionally scanned for "guarantee" language and fasting terms
  (fasting is the next phase, not this one).
- `mode_service.dart` — the only file here allowed to touch
  `HealthStore`. Loads the active config, asks the engine what to
  show, and clears the mode once it auto-completes (the one side
  effect the pure engine can't have).

On Today, an active mode shows as a compact strip between the readout
and Last night: phase, days-to-go, themed action — the readiness card
on day 0. The Modes tab lists all three, lets you set one up (date +
optional label) or end the active one, and asks to replace if you
start a different mode while one's already running.

## What comes next (in order)

1. **Night Shift and Fasting modes** — same mechanic as the event
   modes (this phase's `EventModeEngine`/content-pack machinery was
   built with these as the next extension point; see `ModeId`), but
   ongoing/recurring rather than counting down to a single date.
2. **Settings screen** — data export/delete (the DPDP hook already
   exists in `HealthStore.deleteAllData()`), ring pairing UI.
3. **Health-store adapter** — real data from Apple Health / Health
   Connect (dev tool; see wiki page 6 for the SDNN/RMSSD warning).
4. **eIoT ring adapter** — swap in the real TM21 SDK behind
   `RingAdapter` once eIoT delivers it.

## Deliberate constraints (do not "fix" these)

- Models carry processed metrics only. No raw PPG fields until eIoT
  grants raw access (wiki gate 1).
- Nullable readings are normal, not errors. Missing data is part of
  the contract.
- No accounts, no cloud, no ML in v1 (wiki page 6).
- `fl_chart` is pinned to `^0.66.2`, not the latest 1.x: this Flutter
  SDK (3.32.6) locks `vector_math` to 2.1.4, and fl_chart 1.1.0 calls a
  `Matrix4` method that only exists in a newer `vector_math` than this
  SDK will resolve. 0.66.2 is the newest version that actually compiles
  here — revisit the pin next Flutter SDK upgrade.

## Known issue (not introduced this phase, not yet fixed)

`mock_ring_adapter_test.dart`'s "24h sync returns snapshots and one
night of sleep" depends on the real wall clock rather than an
injectable time source: `MockRingAdapter.syncSince` anchors a night to
23:00 on `since`'s calendar date and only counts it if that's before
`now - 7h`. Run the test in roughly the first 7 hours after local
midnight and the arithmetic can land on zero nights for a 24h window.
Fix belongs in `mock_ring_adapter.dart` (inject `now`, or anchor
differently) — flagged here rather than fixed in this phase, since it
predates and is unrelated to the mode machinery this phase added.
