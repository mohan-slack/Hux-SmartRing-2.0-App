/// Spoken cues for a session — WHAT to say and WHEN. Pure Dart.
///
/// Languages: English (Indian English voice) and Hindi (Devanagari, so the
/// phone's Hindi voice reads it naturally). Other Indian languages fall
/// back to English until reviewed translations are added.
library;

import '../profile/user_profile.dart';
import 'plan_models.dart';

enum CueLanguage { english, hindi }

extension CueLanguageTts on CueLanguage {
  /// BCP-47 tag for the phone's text-to-speech engine.
  String get ttsTag => switch (this) {
        CueLanguage.english => 'en-IN',
        CueLanguage.hindi => 'hi-IN',
      };

  static CueLanguage fromProfile(AppLanguage? l) => l == AppLanguage.hindi ? CueLanguage.hindi : CueLanguage.english;
}

class Cue {
  final int atSecond;
  final String text;
  const Cue(this.atSecond, this.text);
}

class VoiceCues {
  /// Halfway cue only for segments at least this long.
  static const halfwayMinSeconds = 240;

  /// "10 seconds" cue only for segments at least this long.
  static const countdownMinSeconds = 60;

  const VoiceCues._();

  static String _duration(int seconds, CueLanguage l) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    if (l == CueLanguage.hindi) {
      if (min == 0) return '$sec सेकंड';
      return sec == 0 ? '$min मिनट' : '$min मिनट $sec सेकंड';
    }
    if (min == 0) return '$sec seconds';
    final m = min == 1 ? '1 minute' : '$min minutes';
    return sec == 0 ? m : '$m $sec seconds';
  }

  static String _start(Segment s, CueLanguage l) {
    final d = _duration(s.seconds, l);
    if (l == CueLanguage.hindi) {
      return switch (s.kind) {
        SegmentKind.warmup => 'आराम से चलकर वार्म-अप कीजिए, $d।',
        SegmentKind.walk => 'आराम से चलिए, $d।',
        SegmentKind.brisk => 'अब तेज़ चलिए, $d। लगभग सौ कदम प्रति मिनट।',
        SegmentKind.fast => 'अब तेज़ चलिए, $d। सांस थोड़ी फूलनी चाहिए।',
        SegmentKind.slow => 'अब धीरे चलिए, $d।',
        SegmentKind.run => 'अब दौड़िए, $d।',
        SegmentKind.snack => 'अब पूरी ताकत से, $d। सीढ़ियां या तेज़ चढ़ाई।',
        SegmentKind.exercise => s.instruction ?? 'अगली कसरत, $d।',
        SegmentKind.cooldown => 'अब धीरे चलकर कूल-डाउन कीजिए, $d।',
      };
    }
    return switch (s.kind) {
      SegmentKind.warmup => 'Warm up with an easy walk, $d.',
      SegmentKind.walk => 'Walk at a comfortable pace, $d.',
      SegmentKind.brisk => 'Brisk walk now, $d. Aim for about 100 steps a minute.',
      SegmentKind.fast => 'Fast walk now, $d. You should be breathing hard.',
      SegmentKind.slow => 'Slow down and walk easy, $d.',
      SegmentKind.run => 'Start running, $d.',
      SegmentKind.snack => 'Go hard for $d. Stairs or a fast uphill walk.',
      SegmentKind.exercise => s.instruction ?? 'Next exercise, $d.',
      SegmentKind.cooldown => 'Cool down with an easy walk, $d.',
    };
  }

  static String _halfway(CueLanguage l) => l == CueLanguage.hindi ? 'आधा हो गया। बढ़िया, चलते रहिए।' : 'Halfway. Keep going.';
  static String _tenLeft(CueLanguage l) => l == CueLanguage.hindi ? 'दस सेकंड बाकी।' : '10 seconds.';
  static String _done(CueLanguage l) =>
      l == CueLanguage.hindi ? 'सेशन पूरा हुआ। शाबाश!' : 'Session complete. Well done!';

  /// All cues for [session], in time order.
  static List<Cue> forSession(Session session, CueLanguage l) {
    final cues = <Cue>[];
    var t = 0;
    for (final s in session.segments) {
      cues.add(Cue(t, _start(s, l)));
      if (s.seconds >= halfwayMinSeconds) cues.add(Cue(t + s.seconds ~/ 2, _halfway(l)));
      if (s.seconds >= countdownMinSeconds) cues.add(Cue(t + s.seconds - 10, _tenLeft(l)));
      t += s.seconds;
    }
    cues.add(Cue(t, _done(l)));
    return cues;
  }

  /// Cues that became due between [fromSecond] (exclusive) and
  /// [toSecond] (inclusive) — the player calls this every tick, and after
  /// returning from the background only the LATEST missed cue is spoken.
  static List<Cue> due(List<Cue> cues, int fromSecond, int toSecond) {
    final hits = cues.where((c) => c.atSecond > fromSecond && c.atSecond <= toSecond).toList();
    if (hits.length <= 1) return hits;
    return [hits.last];
  }
}

/// Where in a session [elapsedSeconds] falls.
class SessionPosition {
  final int segmentIndex;
  final int secondsLeftInSegment;
  final bool finished;
  const SessionPosition(this.segmentIndex, this.secondsLeftInSegment, this.finished);

  static SessionPosition of(Session s, int elapsedSeconds) {
    var t = 0;
    for (var i = 0; i < s.segments.length; i++) {
      final end = t + s.segments[i].seconds;
      if (elapsedSeconds < end) return SessionPosition(i, end - elapsedSeconds, false);
      t = end;
    }
    return SessionPosition(s.segments.length - 1, 0, true);
  }
}
