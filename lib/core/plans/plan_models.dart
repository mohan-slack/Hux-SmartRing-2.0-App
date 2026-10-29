/// Guided walking & movement plans — data types. Pure Dart.
library;

enum SegmentKind { warmup, walk, brisk, fast, slow, run, snack, exercise, cooldown }

class Segment {
  final SegmentKind kind;
  final int seconds;

  /// Short instruction shown on screen (and spoken for exercises).
  final String? instruction;

  const Segment(this.kind, this.seconds, {this.instruction});
}

class Session {
  final int week; // 1-based
  final int day; // 1-based within the week
  final List<Segment> segments;

  const Session({required this.week, required this.day, required this.segments});

  int get totalSeconds => segments.fold(0, (s, x) => s + x.seconds);
  int get minutes => (totalSeconds / 60).round();
}

enum PlanLevel { gentle, beginner, intermediate, advanced }

extension PlanLevelLabel on PlanLevel {
  String get label => switch (this) {
        PlanLevel.gentle => 'Gentle',
        PlanLevel.beginner => 'Beginner',
        PlanLevel.intermediate => 'Intermediate',
        PlanLevel.advanced => 'Advanced',
      };
}

class Plan {
  final String id;
  final String name;
  final String tagline;

  /// Plain-language "why", with the research it's based on.
  final String evidence;
  final PlanLevel level;
  final int weeks;
  final int sessionsPerWeek;
  final List<Session> sessions;

  /// Ask the readiness check before the first session.
  final bool needsReadinessCheck;

  /// Extra safety note shown on the plan page.
  final String? safetyNote;

  const Plan({
    required this.id,
    required this.name,
    required this.tagline,
    required this.evidence,
    required this.level,
    required this.weeks,
    required this.sessionsPerWeek,
    required this.sessions,
    this.needsReadinessCheck = false,
    this.safetyNote,
  });
}
