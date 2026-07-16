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
lib/core/meaning/    Meaning/Action engine: baseline, scoring, readout
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

## What comes next (in order)

1. **Screens** — Today, Sleep, Trends, Settings, wired to
   `ReadoutService`.
2. **Health-store adapter** — real data from Apple Health / Health
   Connect (dev tool; see wiki page 6 for the SDNN/RMSSD warning).
3. **eIoT ring adapter** — swap in the real TM21 SDK behind
   `RingAdapter` once eIoT delivers it.

## Deliberate constraints (do not "fix" these)

- Models carry processed metrics only. No raw PPG fields until eIoT
  grants raw access (wiki gate 1).
- Nullable readings are normal, not errors. Missing data is part of
  the contract.
- No accounts, no cloud, no ML in v1 (wiki page 6).
