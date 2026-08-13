/// HUX Daily Readout
/// ------------------
/// The output of the Meaning/Action engine: today's Numbers -> Meaning
/// translated into plain English, plus 1-2 things to actually do.
///
/// Wellness product rule (non-negotiable): nothing in here diagnoses,
/// names a disease, or alarms. Worst-case wording is "your body is
/// working harder than usual" — never "you might be sick."

/// How today is read, relative to the user's OWN baseline.
/// [learning] means the baseline itself is insufficient (< 3 days of
/// history) — there is no reading to give yet, just an honest state.
enum RecoveryState { recharged, steady, stretched, rundown, learning }

/// How much of last night's data we actually had to work with.
enum DataQuality { full, partial, sparse }

class DailyReadout {
  final DateTime date;
  final RecoveryState state;

  /// One short plain-English sentence. Keep it under ~60 chars.
  final String headline;

  /// 1-2 sentences on WHY, in the user's own terms ("your HRV was well
  /// below your usual").
  final String meaning;

  /// 1-2 concrete, doable-today suggestions. Never generic filler.
  final List<String> actions;

  final DataQuality dataQuality;

  /// A 0-100 daytime stress figure, HIGHER = more stressed, DISPLAY ONLY
  /// — see meaning_engine.dart for why this never feeds the recovery
  /// score. Null when there isn't enough today-data to derive it.
  final int? stressIndex;

  /// Today's cumulative active-calorie total, DISPLAY ONLY, same
  /// display-not-scored treatment as [stressIndex]. Null when today has
  /// no active-energy readings yet.
  final int? activeEnergyKcal;

  /// The latest heart-rate reading from today's snapshots, DISPLAY ONLY
  /// — same "most recent non-null reading, never scored" treatment as
  /// [stressIndex]/[activeEnergyKcal]. This is what lets a "live" heart-
  /// rate card show a real number immediately on load, rather than
  /// waiting on [RingAdapter.liveSnapshots] to tick again after the app
  /// opens. Null when today has no heart-rate readings yet.
  final int? currentHeartRateBpm;

  const DailyReadout({
    required this.date,
    required this.state,
    required this.headline,
    required this.meaning,
    required this.actions,
    required this.dataQuality,
    this.stressIndex,
    this.activeEnergyKcal,
    this.currentHeartRateBpm,
  });

  /// The "still learning your body" readout shown while the baseline
  /// is being established. Not an error state — a normal early-days one.
  factory DailyReadout.learning(DateTime date, {int daysOfData = 0}) =>
      DailyReadout(
        date: date,
        state: RecoveryState.learning,
        headline: 'Still learning your body',
        meaning: 'HUX builds its readouts from your own patterns, so it '
            'needs a few more days ($daysOfData so far) before it can '
            'tell you what today means for you.',
        actions: const [
          'Keep wearing your ring, including overnight',
          'Check back tomorrow — your baseline is almost ready',
        ],
        dataQuality: DataQuality.sparse,
      );

  /// Shown when the baseline exists but last night produced nothing
  /// usable (no session, or every reading in it was null) and there are
  /// no snapshots to fall back on. Distinct from [learning]: the body is
  /// known, last night just didn't come through.
  ///
  /// [stressIndex]/[activeEnergyKcal]/[currentHeartRateBpm] are still
  /// accepted here: a night with no usable sleep data doesn't mean
  /// today's daytime snapshots (which these are derived from) are
  /// unusable too.
  factory DailyReadout.noSignal(DateTime date,
          {int? stressIndex, int? activeEnergyKcal, int? currentHeartRateBpm}) =>
      DailyReadout(
        date: date,
        state: RecoveryState.learning,
        headline: 'No readings from last night',
        meaning: "We didn't get usable data from last night, so there's "
            'nothing to read into today. This happens — a missed sync or '
            'a night the ring came off.',
        actions: const [
          'Make sure the ring is charged and snug for tonight',
          'Open the app after your next sync to catch up',
        ],
        dataQuality: DataQuality.sparse,
        stressIndex: stressIndex,
        activeEnergyKcal: activeEnergyKcal,
        currentHeartRateBpm: currentHeartRateBpm,
      );
}
