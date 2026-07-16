/// HUX Event Mode Engine
/// -----------------------
/// Turns an [EventModeConfig] + today's date + the day's already-
/// computed [DailyReadout] into a [ModeStrip] to show on Today.
///
/// PURE DART. No Flutter, no storage, no I/O. Modes DECORATE the
/// Meaning engine's output — this file never rescoring anything, it
/// only picks phase-appropriate copy around a readout [MeaningEngine]
/// already produced. Same inputs, same output, always.
///
/// "Days to go" is a CALENDAR date difference in the device's LOCAL
/// timezone — time-of-day on either [EventModeConfig.targetDate] or
/// `today` is ignored, so "the day before" always means the whole day
/// before, not "within 24 hours". Local, not UTC, matters here: see
/// the comment on [_dateOnly].

import '../meaning/daily_readout.dart';
import 'content/event_content.dart';
import 'mode.dart';

/// The coaching phase a mode is in today, driven purely by days-to-go
/// (see [EventModeEngine] thresholds) except for [theDay] (exactly 0)
/// and [completed] (target date has passed).
enum ModePhase { foundation, build, taper, eve, theDay, completed }

/// What to show on Today when an event mode is active.
class ModeStrip {
  final ModePhase phase;
  final String phaseLabel;

  /// 0 on the day itself; negative once the target date has passed
  /// (only ever seen paired with [ModePhase.completed]).
  final int daysToGo;

  /// A short description of what this phase is about — distinct from
  /// [themedAction], which is the specific, concrete suggestion.
  final String focus;

  /// The mode-and-phase-flavored suggestion for today, sourced from
  /// content/event_content.dart.
  final String themedAction;

  /// True only for the one-time "how it went" strip shown when the
  /// mode auto-completes — [ModeService] clears the mode right after
  /// this is produced, so it's never shown twice.
  final bool isWrapUp;

  const ModeStrip({
    required this.phase,
    required this.phaseLabel,
    required this.daysToGo,
    required this.focus,
    required this.themedAction,
    this.isWrapUp = false,
  });
}

class EventModeEngine {
  const EventModeEngine();

  // ---- days-to-go thresholds (inclusive), matching product spec ----
  /// More than this many days out reads as Foundation.
  static const foundationThreshold = 21;

  /// 8..[foundationThreshold] days out reads as Build.
  static const buildMin = 8;

  /// 2..7 days out reads as Taper; below this (i.e. 1) is Eve.
  static const taperMin = 2;

  static const Map<ModePhase, EventPhase> _contentPhaseFor = {
    ModePhase.foundation: EventPhase.foundation,
    ModePhase.build: EventPhase.build,
    ModePhase.taper: EventPhase.taper,
    ModePhase.eve: EventPhase.eve,
  };

  static const Map<ModePhase, String> _labels = {
    ModePhase.foundation: 'Foundation',
    ModePhase.build: 'Build',
    ModePhase.taper: 'Taper',
    ModePhase.eve: 'Eve',
    ModePhase.theDay: 'The day',
    ModePhase.completed: 'Wrapped up',
  };

  static const Map<ModePhase, String> _focus = {
    ModePhase.foundation: 'Build sleep consistency',
    ModePhase.build: 'Protect bedtime, steady routine',
    ModePhase.taper: 'Wind down intensity, no experiments',
    ModePhase.eve: 'Early night, calm evening, everything ready',
    ModePhase.theDay: "Today's the day",
    ModePhase.completed: 'How the week went',
  };

  ModeStrip evaluate({
    required EventModeConfig config,
    required DateTime today,
    required DailyReadout readout,
  }) {
    final daysToGo =
        _dateOnly(config.targetDate).difference(_dateOnly(today)).inDays;

    if (daysToGo < 0) {
      return ModeStrip(
        phase: ModePhase.completed,
        phaseLabel: _labels[ModePhase.completed]!,
        daysToGo: daysToGo,
        focus: _focus[ModePhase.completed]!,
        themedAction: EventContent.pickWrapUp(config.id, today),
        isWrapUp: true,
      );
    }

    if (daysToGo == 0) {
      return ModeStrip(
        phase: ModePhase.theDay,
        phaseLabel: _labels[ModePhase.theDay]!,
        daysToGo: 0,
        focus: _focus[ModePhase.theDay]!,
        themedAction:
            EventContent.pickDayZeroAction(config.id, readout.state, today),
      );
    }

    final phase = _phaseFor(daysToGo);
    return ModeStrip(
      phase: phase,
      phaseLabel: _labels[phase]!,
      daysToGo: daysToGo,
      focus: _focus[phase]!,
      themedAction: EventContent.pickPhaseAction(
          config.id, _contentPhaseFor[phase]!, today),
    );
  }

  ModePhase _phaseFor(int daysToGo) {
    if (daysToGo > foundationThreshold) return ModePhase.foundation;
    if (daysToGo >= buildMin) return ModePhase.build;
    if (daysToGo >= taperMin) return ModePhase.taper;
    return ModePhase.eve; // daysToGo == 1 (0 and negative handled above)
  }

  /// Truncates to a calendar date in the DEVICE'S LOCAL timezone, not
  /// UTC. "Days to go" is inherently a local-wall-clock concept — a
  /// wedding "on the 26th" means the 26th where the user is standing.
  /// [EventModeConfig.targetDate] round-trips through storage as UTC
  /// (this app's usual convention — see sqlite_health_store.dart), so
  /// converting back to local here matters: truncating a UTC instant
  /// to Y/M/D directly can land on the wrong calendar day by the
  /// user's own clock (e.g. IST is UTC+5:30 — anything from 18:30 UTC
  /// onward is already "tomorrow" locally).
  DateTime _dateOnly(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
