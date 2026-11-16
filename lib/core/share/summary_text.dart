/// The day or week as a short WhatsApp message (*bold* is WhatsApp's own
/// markup). Only lines with real data are included; nothing is sent by
/// HUX — the user picks the chat and taps send. Pure.
library;

import '../progress/goal_score.dart';

class SummaryText {
  SummaryText._();

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const footer = '_Sent from HUX_';

  static String _n(num v) {
    final s = v.round().toString();
    return s.length > 3 ? '${s.substring(0, s.length - 3)},${s.substring(s.length - 3)}' : s;
  }

  static String _hm(int minutes) => minutes % 60 == 0 ? '${minutes ~/ 60} h' : '${minutes ~/ 60} h ${minutes % 60} min';

  /// Today so far. Null when fewer than two things have data (an almost
  /// empty message isn't worth sending).
  static String? daily({
    required DateTime now,
    String? name,
    int? charge,
    String? chargeLabel,
    int? sleepMin,
    int? steps,
    int? stepGoal,
    int? proteinG,
    int? proteinGoalG,
    int? kcal,
    int? waterGlasses,
    int? waterGoal,
    int? streakDays,
  }) {
    final lines = <String>[
      if (charge != null) '⚡ Charge $charge${chargeLabel == null || chargeLabel.isEmpty ? '' : ' · $chargeLabel'}',
      if (sleepMin != null && sleepMin >= 60) '😴 Sleep ${_hm(sleepMin)}',
      if (steps != null && steps > 0) '👣 Steps ${_n(steps)}${stepGoal == null ? '' : ' of ${_n(stepGoal)}'}',
      if (proteinG != null && proteinG > 0)
        '🍛 Protein $proteinG${proteinGoalG == null ? ' g' : ' of $proteinGoalG g'}'
            '${kcal == null || kcal <= 0 ? '' : ' · ${_n(kcal)} kcal'}',
      if (waterGlasses != null && waterGlasses > 0)
        '💧 Water $waterGlasses${waterGoal == null ? '' : ' of $waterGoal'} glasses',
      if (streakDays != null && streakDays >= 2) '🔥 $streakDays-day streak',
    ];
    if (lines.length < 2) return null;
    final l = now.toLocal();
    final who = name == null || name.trim().isEmpty ? 'My day' : "${name.trim()}'s day";
    return [
      '*$who with HUX* — ${_days[l.weekday - 1]} ${l.day} ${_months[l.month - 1]}',
      ...lines,
      footer,
    ].join('\n');
  }

  /// Last week's score. Null when fewer than two parts have data.
  static String? weekly(WeekScore w, {String? name, double? weightChangeKg}) {
    final overall = w.overall;
    final parts = [for (final p in w.parts.values) if (p.hasData) p];
    if (overall == null || parts.length < 2) return null;
    final change = w.change;
    const icons = {ScorePart.sleep: '😴', ScorePart.energy: '⚡', ScorePart.move: '👣', ScorePart.food: '🍛'};
    final who = name == null || name.trim().isEmpty ? 'My week' : "${name.trim()}'s week";
    return [
      '*$who with HUX: $overall/100*'
          '${change == null || change == 0 ? '' : change > 0 ? ' (up $change)' : ' (down ${-change})'}',
      for (final p in parts) '${icons[p.part]} ${p.part.label} ${p.score}',
      if (weightChangeKg != null && weightChangeKg.abs() >= 0.1)
        '⚖️ Weight ${weightChangeKg < 0 ? '−' : '+'}${weightChangeKg.abs().toStringAsFixed(1)} kg',
      footer,
    ].join('\n');
  }
}
