/// How the onboarding answers tune the numbers. Pure, no I/O.
///
/// Every rule is small and explained, so the app never quietly treats
/// people differently in ways they can't see:
/// - Sleep minimum: 7 h for adults (AASM/SRS), 7 h 30 for students and
///   anyone whose goal is "Sleep better" (young adults and sleep goals
///   do better with the higher end of 7–9 h). Older adults stay at 7 h
///   (7–8 h guide for 65+).
/// - Gentle effort wording for older adults: retired, "Stay active"
///   goal, or a profile set up for a parent.
/// - Wearable "phone only": Charge says it's based on less data.
library;

import '../profile/user_profile.dart';
import 'hux_charge.dart';

class ProfileTuning {
  final Duration minSleep;
  final bool gentleEffort;

  /// No ring/watch: fewer signals, so numbers are rougher.
  final bool phoneOnly;

  const ProfileTuning({
    this.minSleep = HuxChargeCalculator.minHealthySleep,
    this.gentleEffort = false,
    this.phoneOnly = false,
  });

  static const standard = ProfileTuning();

  factory ProfileTuning.of(UserProfile? p) {
    if (p == null) return standard;
    final older = p.dayType == DayType.retired || p.goals.contains(Goal.activeElder) || p.audience == Audience.parent;
    final higherSleep = !older && (p.dayType == DayType.student || p.goals.contains(Goal.sleepBetter));
    return ProfileTuning(
      minSleep: higherSleep ? const Duration(hours: 7, minutes: 30) : HuxChargeCalculator.minHealthySleep,
      gentleEffort: older,
      phoneOnly: p.wearable == Wearable.phoneOnly,
    );
  }
}
