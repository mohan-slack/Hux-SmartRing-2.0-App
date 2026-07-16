/// HUX Event Mode Content
/// ------------------------
/// Themed action packs for the three EVENT modes (Big Day, Shaadi,
/// Exam Season) — same mechanic, three registers. Pure Dart, same
/// rules as Desi Plate (content/action_content.dart): deterministic by
/// `date.day`, wellness wording only, forbidden-words-tested.
///
/// Shaadi gets one extra, non-negotiable rule: coach ENERGY and CALM,
/// never appearance. No "look slimmer/better", no weight talk, ever —
/// see the guardrail scan in test/event_content_test.dart.

import '../../meaning/daily_readout.dart';
import '../mode.dart';

/// The four coaching phases that get date-seeded variants. "The day"
/// (day 0) and the post-date wrap-up are structured differently — see
/// [EventContent.pickDayZeroAction] and [EventContent.pickWrapUp].
enum EventPhase { foundation, build, taper, eve }

/// A coarse bucket for day-0 readiness copy, derived from the day's
/// [RecoveryState] — see [EventContent.pickDayZeroAction]. Keeps the
/// content matrix small (3 buckets, not 5 states) while still reading
/// as "from the readout", per spec.
enum _Readiness { ready, gentle, neutral }

class EventContent {
  const EventContent._();

  static const Map<ModeId, Map<EventPhase, List<String>>> _phaseLibrary = {
    ModeId.bigDay: {
      EventPhase.foundation: [
        'Weeks out is the best time to lock in a steady sleep schedule '
            '— start now, not the night before',
        'Build your routine around the big day early: consistent '
            'meals, consistent bedtime',
        "Use this quiet stretch to test your prep routine, not just "
            "the material — how you'll eat and sleep matters too",
      ],
      EventPhase.build: [
        'Keep bedtime consistent this week — the big day rewards '
            'routine, not a scramble',
        "Protect your sleep this week; it's doing more for the big day "
            'than one more late night of prep',
        'Steady meals, steady sleep — let the routine carry you '
            'through this stretch',
      ],
      EventPhase.taper: [
        'Ease off any new routines now — this is not the week to try '
            'something different',
        'Wind down intensity this week; save your energy for the day '
            'itself',
        'Keep meals familiar and light this week — nothing '
            'experimental before the big day',
      ],
      EventPhase.eve: [
        'Tonight: an early, calm evening. Lay out everything you need '
            'so tomorrow starts easy',
        'Keep tonight low-key — a light dinner, an early wind-down, '
            'and lights out on time',
        "Everything's ready — tonight is just about a calm evening "
            'and good sleep',
      ],
    },
    ModeId.shaadi: {
      EventPhase.foundation: [
        'Weeks before the wedding is the best time to build a steady '
            'sleep rhythm — start now, before the calendar fills up',
        'Early days: let your routine settle before the wedding '
            'season gets busy',
        "This is the calm stretch — use it to build habits that'll "
            'carry you through wedding week',
      ],
      EventPhase.build: [
        'Wedding prep gets loud — protect your sleep through it, '
            "that's what keeps your energy up",
        'Keep mealtimes steady this week, even as the to-do list '
            'around the wedding grows',
        'Guard your bedtime this week — the functions will ask a lot '
            'of your energy later',
      ],
      EventPhase.taper: [
        'This close to the wedding, keep things familiar — no new '
            'routines, no new foods to try',
        'Ease off intense workouts this week — save the energy for '
            'the functions',
        'Keep this week calm and steady — let the wedding excitement '
            'stay outside your sleep schedule',
      ],
      EventPhase.eve: [
        "Tonight: an early night, however excited you are — tomorrow "
            "needs your energy, not your alarm clock",
        'Keep tonight calm — lay out what you need, wind down early, '
            'let sleep do its job before the big day',
        'One calm, early night tonight — everything else is ready',
      ],
    },
    ModeId.examSeason: {
      EventPhase.foundation: [
        'Weeks before the exam is the time to fix your study-sleep '
            "schedule — don't wait for the final stretch to sort it out",
        'Build a steady study routine now — consistent blocks beat '
            'marathon sessions later',
        "Early prep: protect your sleep now so the last weeks don't "
            'have to pay for it',
      ],
      EventPhase.build: [
        "Keep study blocks steady this week — protect sleep, it's "
            'doing as much work as revision',
        'An hour of sleep beats a 4am cram — build that habit now, '
            'before exam week',
        "Steady meals between study blocks — don't let revision eat "
            'into proper food breaks',
      ],
      EventPhase.taper: [
        'This close to the exam, protect sleep over one more topic — '
            "revision now, cramming doesn't help",
        'Ease off new topics this week — consolidate what you know, '
            'rest matters more now',
        'Keep this week steady — familiar food, familiar routine, no '
            'new study techniques to test',
      ],
      EventPhase.eve: [
        'Tonight: pack your admit card and stationery, then close the '
            'books early — sleep is your last revision',
        "An hour of sleep beats a 4am cram — tonight, that's truer "
            'than ever. Lights out early',
        "Everything's ready for tomorrow — tonight is about rest, not "
            'one more chapter',
      ],
    },
  };

  static const Map<ModeId, Map<_Readiness, List<String>>> _dayZeroLibrary = {
    ModeId.bigDay: {
      _Readiness.ready: [
        "You're in good shape for today — trust your prep and go",
        "Your body's ready — channel that into the big day",
        'Solid recovery overnight — a good sign heading into today',
      ],
      _Readiness.gentle: [
        "Your body's asking for an easier start today — pace yourself "
            'into the big day',
        "A slower start today is fine — ease in, you've done the prep",
        "Take today at your own pace — the prep is already done, "
            'trust it',
      ],
      _Readiness.neutral: [
        "Not much data to read this morning — go with how you feel "
            'and trust your prep',
        "Today's the day — lean on your preparation, whatever the "
            'numbers say',
        "Focus on the big day itself today — you've done the "
            'groundwork',
      ],
    },
    ModeId.shaadi: {
      _Readiness.ready: [
        "You're well-rested and ready — enjoy the day",
        'Good energy heading in — let today be as joyful as '
            "you've planned",
        "You're in a good place for today — soak it in",
      ],
      _Readiness.gentle: [
        'Pace yourself today — long functions ask a lot, so take '
            'breaks when you can',
        'Ease into today — sip water, take a breather between '
            'functions, and let the day come to you',
        'Today will be long — pace yourself and lean on the people '
            'around you',
      ],
      _Readiness.neutral: [
        "Not much to read this morning — go with the day's flow and "
            'enjoy it',
        "Today's the day — let the celebrations carry you",
        'Focus on the moment today — the numbers can wait',
      ],
    },
    ModeId.examSeason: {
      _Readiness.ready: [
        "You're well-rested — trust your prep and go in steady",
        'Good recovery overnight — a solid base for exam day',
        "You're in good shape for today — let your preparation do "
            'the talking',
      ],
      _Readiness.gentle: [
        "Take today at a steady pace — you've done the work, let "
            'your body ease into it',
        'A slower start today is fine — trust the preparation, not '
            'the nerves',
        'Go easy on yourself this morning — the prep is done, '
            "today's just showing up",
      ],
      _Readiness.neutral: [
        'Not much to read this morning — focus on the paper, not the '
            'numbers',
        "Today's the exam — lean on your preparation, whatever the "
            'morning looks like',
        'Focus on the exam itself today — the groundwork is already '
            'done',
      ],
    },
  };

  static const Map<ModeId, List<String>> _wrapUpLibrary = {
    ModeId.bigDay: [
      "The big day has passed — here's how the run-up went: your "
          'routine mostly held together this week',
      "That's the big day done — looking back, your sleep and energy "
          'through the week give a decent picture of how you paced it',
      'Big day complete — this mode has wrapped up; check Story for '
          'how the week actually went',
    ],
    ModeId.shaadi: [
      "The wedding's done — here's to a memorable week. Check Story "
          'for how the past week actually went for your body',
      'Wedding week wrapped up — take a few easy days now to recover '
          'from all the celebrating',
      "That's the wedding behind you — a good time to ease back into "
          'your regular rhythm',
    ],
    ModeId.examSeason: [
      "Exam day's behind you now — check Story for how the past week "
          'actually went',
      "That's the exam done — take a proper rest day, you've earned "
          'it',
      'Exam season wrapped up — ease back into your regular routine '
          'over the next few days',
    ],
  };

  /// A phase-appropriate themed action, picked deterministically by
  /// `date.day` (same convention as Desi Plate).
  static String pickPhaseAction(ModeId id, EventPhase phase, DateTime date) {
    final variants = _phaseLibrary[id]?[phase] ?? const [];
    if (variants.isEmpty) return '';
    return variants[date.day % variants.length];
  }

  /// The day-0 readiness line, derived from the day's [RecoveryState]
  /// (bucketed into ready/gentle/neutral — see [_Readiness]) and
  /// picked deterministically by `date.day`.
  static String pickDayZeroAction(
      ModeId id, RecoveryState state, DateTime date) {
    final variants = _dayZeroLibrary[id]?[_readinessFor(state)] ?? const [];
    if (variants.isEmpty) return '';
    return variants[date.day % variants.length];
  }

  /// The one-time "how it went" wrap-up shown when the mode auto-
  /// completes (target date has passed).
  static String pickWrapUp(ModeId id, DateTime date) {
    final variants = _wrapUpLibrary[id] ?? const [];
    if (variants.isEmpty) return '';
    return variants[date.day % variants.length];
  }

  static _Readiness _readinessFor(RecoveryState state) {
    switch (state) {
      case RecoveryState.recharged:
      case RecoveryState.steady:
        return _Readiness.ready;
      case RecoveryState.stretched:
      case RecoveryState.rundown:
        return _Readiness.gentle;
      case RecoveryState.learning:
        return _Readiness.neutral;
    }
  }

  /// Every string in the library, flattened — for the forbidden-words
  /// and appearance/weight-language content scans. Not used by the
  /// engine itself.
  static List<String> get allStrings => [
        ..._phaseLibrary.values
            .expand((byPhase) => byPhase.values)
            .expand((variants) => variants),
        ..._dayZeroLibrary.values
            .expand((byReadiness) => byReadiness.values)
            .expand((variants) => variants),
        ..._wrapUpLibrary.values.expand((variants) => variants),
      ];
}
