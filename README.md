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
lib/core/ring/       Data models, adapter interface, mock TM21, dev-only
                     Health-Store adapter (health_adapter/), data source switch
lib/core/storage/    HealthStore interface + SQLite implementation
lib/core/sync/       SyncService: overlap, retry, watermark
lib/core/meaning/    Meaning/Action engine: baseline, scoring, readout,
                     Desi Plate action content, Weekly Body Story,
                     sleep wording (Night Shift), Fasting Companion pack
lib/core/trends/     Pure per-night chart data (gaps, personal band)
lib/core/modes/      Mode machinery: event modes (Big Day, Shaadi, Exam
                     Season) + lifestyle modes (Night Shift, Fasting)
lib/screens/         Today, Trends, Story, Modes — one tabbed app shell
lib/theme/           Design tokens + the one ThemeData every screen renders under
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
Meaning engine, re-aimed at either a life moment (an EVENT mode — a
target date, phased coaching leading up to it, a readiness message on
the day itself) or how the user lives day to day (a LIFESTYLE mode —
no date, just a change in voice/advice while it's active). Three event
themes so far (Big Day, Shaadi, Exam Season) plus two lifestyle modes
this phase (Night Shift, Fasting Companion) — see below for how the
two kinds differ and coexist.
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
  additionally scanned for "guarantee" language and fasting terms —
  fasting has its own dedicated lifestyle mode and content pack (see
  below), so it has no business showing up in an EVENT mode's copy.
- `mode_service.dart` — the only file here allowed to touch
  `HealthStore`. Loads the active config, asks the engine what to
  show, and clears the mode once it auto-completes (the one side
  effect the pure engine can't have).

On Today, an active mode shows as a compact strip between the readout
and Last night: phase, days-to-go, themed action — the readiness card
on day 0. The Modes tab lists all three, lets you set one up (date +
optional label) or end the active one, and asks to replace if you
start a different mode while one's already running.

**Lifestyle modes** — Night Shift and Fasting Companion — are the
second kind of mode this phase adds. Where an EVENT mode counts down to
a date, a LIFESTYLE mode describes how the user lives right now and
changes the app's voice/advice while it's active: no target date, no
phases, no auto-complete. At most one of each kind is active at a
time, but a lifestyle mode CAN run alongside the active event mode
(and alongside each other) — they answer different questions. Both are
keyed under `LifestyleModeId` in the same `mode_state` table event
modes already use (`mode_id` is just a different string per kind) —
**no schema migration was needed**, since `mode_state(mode_id TEXT
PRIMARY KEY, json TEXT)` already accepts arbitrary keys.
- **Night Shift** (`NightShiftConfig`: usual sleep start/end hour) —
  when active, `sleep_wording.dart`'s `SleepWording` swaps every
  "last night" / "overnight" / "tonight" in the readout for "last
  sleep" / "during your last sleep" / "before your next sleep", in
  ONE place — `MeaningEngine` takes a plain `nightShiftActive` bool and
  never imports anything from `core/modes`, keeping the engine pure.
  Baseline and staleness logic already work on the user's own sleep
  *sessions*, not clock hours, so a 9am–4pm sleeper needs no scoring
  changes — just the wording swap.
- **Fasting Companion** (`FastingConfig`: type — Roza, Navratri,
  Ekadashi, Karwa Chauth, or custom — plus a date range and an optional
  eating window) — on an active fast day, `ActionContent`'s library is
  filtered by a new `ActionTag` on every existing action
  (`daytimeFood`/`eveningFood`/`activity`/`sleep`/`breathing`/`neutral`);
  `MeaningEngine` takes a plain `excludeDaytimeFood` bool and drops any
  `daytimeFood`-tagged action, so a fasting user is never told to have
  lunch or afternoon chai. `content/fasting_content.dart` is a small
  (~15-string) pack `ReadoutService` layers one pick from into today's
  actions — sleep-honesty (suhoor/sehri-specific for Roza, generic
  elsewhere), eating-window-relative hydration, energy pacing, wind-
  down, and a day-N acknowledgement ("day 4 of Roza — your numbers
  reflect the observance, not a problem"). Hard rule, tested by scan:
  never advises breaking, shortening, or skipping the fast. Weekly Body
  Story adds one neutral observation when 3+ days of the week fall
  inside an active fast.
- On Today, active lifestyle modes show as a single one-line context
  chip under the headline ("Night shift", "Roza — day 4", or both) —
  never a second card; the readout stays the hero even with an event-
  mode strip also showing. The Modes screen's new Lifestyle section
  lists both with their own setup (hour pickers for Night Shift; fast
  type + date range + optional eating window for Fasting) and shows
  active ones as compact chips with an End affordance.
- `ReadoutService` and `WeeklyStoryService` are the only files that
  assemble lifestyle context from storage; `readout_service.dart`
  takes an optional `ModeService` (defaulting to no lifestyle modes
  active, so every existing caller/test is unaffected) purely to build
  that context and layer in the Fasting Companion action — the
  filtering decision itself still happens inside `MeaningEngine` via
  the two plain booleans above.

## Health-Store adapter (dev tool, not user-facing)

`lib/core/ring/health_adapter/` is the SECOND real `RingAdapter`
implementation (after the mock): it reads REAL data from Apple Health
(iOS) / Google Health Connect (Android) via the `health` package and
maps it through the exact same pipeline the mock and the eventual eIoT
adapter use. Purpose: exercise the Meaning engine, Modes, Story, and
Trends against real human data before the eIoT ring exists. It is
**read-only** (no write permissions, ever requested) and is impossible
to confuse with either the demo or a real ring — see the source switch
below.

- `health_mappers.dart` — **pure Dart.** `mapHrSamples`/`mapHrvSamples`/
  `mapSpo2`/`mapBodyTemp`/`mapSteps` bucket raw `HealthDataPoint`s onto
  the same 10-minute grid the mock ring uses (`steps` specifically
  re-derives the ring model's "cumulative since midnight" contract,
  which HealthKit/Health Connect don't report natively);
  `mergeSnapshots` combines the per-metric outputs into one multi-
  metric `HealthSnapshot` per bucket. `mapSleepSessions` clusters raw
  sleep-stage points into nights by ELAPSED TIME (a gap of 2h+ starts a
  new night), not calendar date — so a night crossing midnight is still
  one session. Every function is unit-tested with hand-built points
  (overlaps, gaps, a midnight-spanning night, stage-less sources).
  - **HRV NOTE** (wiki page 6): Apple Health reports HRV as SDNN;
    Health Connect can report RMSSD — HUX rings use RMSSD. These are
    DIFFERENT algorithms on different scales. This adapter exists to
    test the PIPELINE, never to calibrate `MeaningEngine`'s thresholds
    — don't tune `hrvGoodPct`/etc. against data synced through it.
    `HealthStoreRingAdapter` requests SDNN on iOS and RMSSD on Android
    specifically because querying RMSSD on Apple Health doesn't just
    return empty — it throws ("Not available on platform appleHealth").
  - **STAGE-LESS SLEEP**: never fabricated. A source with only a
    generic "asleep" block (`SLEEP_ASLEEP`, no deep/light/REM
    breakdown) maps its whole block to `light` and is flagged via
    `MappedSleepSession.hadRealStages = false` (logged by the adapter).
    The SAME applies to `SLEEP_IN_BED` — what Apple Health's own
    "Add Data" UI writes for a plain manually-entered sleep span, with
    no "asleep" signal at all, only "in bed". Treating it as stage-less
    sleep rather than silently discarding it is what makes the
    simulator trick below actually work; a real sleep-tracking app or
    Apple Watch reports proper staged data instead. Either way, deep/
    REM will read as under-reported for a stage-less night.
- `health_store_ring_adapter.dart` — the adapter itself. `connect()`
  calls `Health().configure()` then `requestAuthorization()` for HR,
  HRV, SpO2, sleep, steps, and body temperature; a refusal (or any
  error reaching the health app) throws a calm `RingConnectionException`
  — same recoverable path the UI already has for a failed ring sync,
  no special-casing needed. `syncSince` queries each health data type
  INDIVIDUALLY (not one batched call) so one unsupported or quietly-
  denied type can't take the whole sync down. `liveSnapshots`/
  `batteryPercent` are real (empty) broadcast streams that simply never
  emit — there's no live-feed or battery concept for a phone reading
  its own health app. `vibrate()` is a no-op. Every non-simulator-
  dependent behavior (permission granted/denied/erroring, the platform-
  specific HRV type, read-only contract) is covered by
  `health_store_ring_adapter_test.dart`, which subclasses the `health`
  package's `Health` (a plain, non-final class) with every method the
  adapter calls overridden — no platform channel, no real HealthKit
  connection, ever involved, which is what makes the permission-denied
  path regression-proof (iOS won't let you re-trigger that system
  sheet once a decision's been made, so it isn't practically re-
  testable by hand more than once per install).

**Choosing the source** — `main.dart` picks the adapter via
`const _sourceEnv = String.fromEnvironment('HUX_SOURCE', defaultValue: 'mock')`,
the ONE place the choice is made; everything above it only ever talks
to `RingAdapter`. Run normally for the mock (unchanged, default); pass
`--dart-define=HUX_SOURCE=health` to use the Health-Store adapter
instead. The banner pinned above every tab (`lib/core/ring/
data_source.dart` + `app_shell.dart`'s `_SourceBanner`) always follows
the source truthfully: amber "DEMO — simulated ring data" for mock,
distinct blue-grey "DEV — your health app data (not a HUX ring)" for
health — tested in `app_shell_test.dart`, including that the default
(mock) is exactly byte-for-byte what it was before this adapter existed.

**Platform setup this phase required:**
- iOS: `NSHealthShareUsageDescription`/`NSHealthUpdateUsageDescription`
  in `Info.plist`, a HealthKit entitlement (`Runner.entitlements`,
  wired into all three build configs via `CODE_SIGN_ENTITLEMENTS`), and
  the deployment target bumped from 12.0 to **14.0** everywhere
  (`Podfile` + all three `IPHONEOS_DEPLOYMENT_TARGET` build settings)
  — the `health` package requires iOS 14+.
- Android: read-only Health Connect permissions + a package-visibility
  `<queries>` entry (to check Health Connect is installed) in
  `AndroidManifest.xml`, `MainActivity` changed from `FlutterActivity`
  to `FlutterFragmentActivity` (needed for `registerForActivityResult`
  when requesting permissions on Android 14+), per the `health`
  package's own setup docs. Not yet verified on a real device/emulator
  this phase — iOS Simulator was the verification path (see below).

**Verifying with the iOS Simulator's Health app** (no real device
needed): the Simulator ships with a real, working Health app. Open it
separately, Browse → (e.g.) Heart → Heart Rate → "Add Data", or
Sleep → "Add Data" (note: this basic manual entry writes `SLEEP_IN_BED`,
not `SLEEP_ASLEEP` — see the STAGE-LESS SLEEP note above, which is
exactly why this adapter treats that type as stage-less rather than
ignoring it). Add sleep entries for **3+ separate nights** — the
Meaning engine needs 3+ nights of history before it computes a real
readout instead of "still learning" — then run HUX with
`--dart-define=HUX_SOURCE=health` and pull-to-refresh Today. If nothing
shows up, double-check Settings → Privacy & Security → Health → Data
Access & Devices → HUX App — HealthKit only shows its permission sheet
ONCE per install; if you need a truly fresh permission prompt, uninstall
the app first (`xcrun simctl uninstall <device> in.co.hux.huxApp` on
the simulator), since revoking access via Settings after already
granting it doesn't reliably make `requestAuthorization` report denied
again on iOS (a documented HealthKit privacy limitation, not a bug
here) — the app will just harmlessly re-sync nothing new and keep
showing whatever was last cached.

## Design system

This phase changed how the app LOOKS, not what it does — every screen
keeps the exact widget types, literal text, and behavior earlier
phases' tests already lock in; only typography, color, and spacing
changed. `lib/theme/` is the whole design system, in two files:

- `hux_tokens.dart` — the ONLY place a hex code or a spacing/radius
  number is allowed to exist. `HuxColors` (ink, paper, card, hairline,
  mutedText, the mint/deep-teal brand accents, the five recovery-state
  colors, and the two source-banner colors), `HuxRadii` (card 20, chip
  999), `HuxSpacing` (the 4/8/12/16/24/32 scale, named `xs`..`xxl`
  rather than left as bare numbers so a screen reads "space it like a
  section gap," not a mystery `24.0`), and `HuxOpacity` (named tint
  strengths — header wash, target band, icon-chip backdrop, active-
  card wash — so "how strong is a wash" is one tunable, not a dozen
  scattered `withValues(alpha:)` calls drifting apart). Two small
  helpers live here too: `RecoveryStateColor` (the one place
  `RecoveryState` maps to a color) and `HuxModeAccent` (the one mint/
  deep-teal accent every mode's icon chip shares, rather than a
  different invented color per mode). Component DIMENSIONS that aren't
  spacing per se — an icon's pixel size, a chart's fixed height — are
  deliberately left as plain numbers; the tokenized scale is for
  layout spacing and brand color, not every numeral in the file.
- `hux_theme.dart` — builds the one `ThemeData` (`buildHuxTheme()`)
  every screen renders under via `HuxApp`. Display/headline text-theme
  slots are Fraunces (serif, warm, editorial) — Today's hero headline
  sits in `displaySmall` at 36, the top of the brand's 32-36 range;
  Story's title and Modes'/Trends' section headers use `headlineSmall`
  at 24. Everything else (body copy, numerals, UI labels/chrome) is
  Space Grotesk, including `bodyLarge` at 1.6 line height specifically
  for Story's paragraphs. `ColorScheme.fromSeed` (seeded on the deep-
  teal accent, not Flutter's purple-ish default) is then `.copyWith()`-
  pinned on every slot the app actually reads (primary/secondary/
  tertiary + their containers, error, surface) so there is no default
  Material purple anywhere, in the theme or in its algorithmic
  derivations. Card/chip/nav-bar/segmented-button/snackbar/progress-
  indicator/dialog/list-tile/input/button themes are all set here too
  — `RefreshIndicator` needs no explicit theme entry since it already
  derives its spinner color from `colorScheme.primary` by default.

Fonts come from the `google_fonts` package (the one new dependency this
phase allowed) — it fetches each weight/style over the network on
first use and caches it on-device afterward; no font files are bundled
as assets. This sandbox/CI environment has network access to
`fonts.gstatic.com`, confirmed empirically before committing to this
approach, and the same is true of a real device/simulator. If a future
environment can't reach it, `GoogleFonts.config.allowRuntimeFetching`
can be set to `false` and/or the fonts bundled as assets per the
package's own README — deliberately not done this phase since it isn't
needed here.

Per-screen highlights:
- **Today** — the readout is the hero: a soft `RecoveryState`-tinted
  wash sits behind the whole header block (headline + "why" sentence +
  lifestyle chip), the recovery dot and each action's leading dot both
  use the same state color, and Last-sleep's numbers are big Space
  Grotesk numerals with a small muted unit alongside (`62 ms`, not one
  plain string) rather than one same-size string.
- **Trends** — bars and lines use the deep-teal brand accent (not
  `colorScheme.primary`, deliberately, so the charts look the same
  regardless of what wraps the screen); the personal sleep-duration
  band is mint at low opacity. Two additions: single-letter weekday
  initials under the sleep bars (thinned to roughly one label per 7
  nights on the 30-day view, so they don't crowd into an unreadable
  smear), and a small muted "low–high unit" hint next to the HRV/HR
  chart titles. Gaps are still gaps — a missing night was never a
  visible zero before this phase and still isn't.
- **Story** — "For next week" is now its own mint-tinted card, visually
  distinct from the observations above it, which read at 1.6 line
  height for comfortable long-form reading.
- **Modes** — every mode and lifestyle tile gets the same circular
  mint-backdrop/deep-teal-glyph icon chip (a consistent brand accent,
  not a different invented color per mode); the active mode's card and
  list tile both pick up the mint wash, and the "End mode" button is
  themed via the app-wide `OutlinedButtonThemeData`.
- **The DEMO/DEV banners** keep their exact meaning and text from
  before, moved into tokens (`HuxColors.demoAmber`/`devBlueGrey`) —
  `devBlueGrey` (`#455A64`) is deliberately darker than Material's
  stock `Colors.blueGrey` swatch (`#607D8B`), which only clears about
  4.0:1 contrast against white text; `#455A64` clears ~7.2:1.

Accessibility checked this phase: every token text/background pairing
actually used for text is >=4.5:1 (ink-on-paper ~15:1, mutedText-on-
paper ~5.2:1, the two banners as above); every themed button has a
44px minimum tap target (`huxMinTapTarget`); and Today is covered by a
widget test that renders at `TextScaler.linear(1.3)` and asserts no
layout exception — verified again by hand on a real simulator at
iOS's own Larger-Text setting.

No dark mode this phase, on purpose — `HuxColors` is deliberately flat
static constants (not yet a light/dark pair) so a dark variant is a
contained addition later, not a rewrite: the day it's needed, the
class becomes a small pair and `hux_theme.dart` picks one based on
`Brightness`.

## What comes next (in order)

1. **Settings screen** — data export/delete (the DPDP hook already
   exists in `HealthStore.deleteAllData()`), ring pairing UI.
2. **eIoT ring adapter** — swap in the real TM21 SDK behind
   `RingAdapter` once eIoT delivers it; `HealthStoreRingAdapter` is a
   worked example of "a second real `RingAdapter` implementation slots
   in without touching a single screen."

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
- Fasting content deliberately reuses generic phrasing across fast
  types where it makes sense ("Navratri/Ekadashi phrasing kept generic
  enough to share") — unlike Desi Plate and the event-mode content
  packs, `FastingContent.allStrings` is not expected to be fully
  duplicate-free; only Desi Plate/Event Content carry that stricter bar.

## Previously known issue (fixed this phase)

`mock_ring_adapter_test.dart`'s "24h sync returns snapshots and one
night of sleep" used to depend on the real wall clock: it anchored a
night to 23:00 on `since`'s calendar date and only counted it if that
was before `now - 7h`, so running it in the first ~7h after local
midnight could land on zero nights for a 24h window. Fixed in
`mock_ring_adapter.dart` by anchoring the first candidate bedtime to
elapsed time since `since` (not `since`'s calendar date), so the count
depends only on the sync window's length, never on the wall-clock hour
it happens to run at. The assertion is now `sleepSessions.length == 1`
for a 24h window, not just `>= 1`.
