/// Onboarding answers -> sleep minimum and effort wording.
/// Run with: flutter test test/profile_tuning_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/meaning/profile_tuning.dart';
import 'package:hux_app/core/profile/user_profile.dart';

void main() {
  const h7 = Duration(hours: 7), h7h30 = Duration(hours: 7, minutes: 30);

  test('no profile / skipped onboarding -> standard 7 h', () {
    expect(ProfileTuning.of(null).minSleep, h7);
    expect(ProfileTuning.of(const UserProfile()).gentleEffort, isFalse);
  });

  test('students and "Sleep better" aim for 7 h 30', () {
    expect(ProfileTuning.of(const UserProfile(dayType: DayType.student)).minSleep, h7h30);
    expect(ProfileTuning.of(const UserProfile(goals: [Goal.sleepBetter])).minSleep, h7h30);
    expect(ProfileTuning.of(const UserProfile(dayType: DayType.desk, goals: [Goal.loseWeight])).minSleep, h7);
  });

  test('older adults: gentle effort, 7 h (not pushed higher)', () {
    for (final p in const [
      UserProfile(dayType: DayType.retired),
      UserProfile(goals: [Goal.activeElder]),
      UserProfile(audience: Audience.parent, goals: [Goal.sleepBetter]),
    ]) {
      final t = ProfileTuning.of(p);
      expect(t.gentleEffort, isTrue);
      expect(t.minSleep, h7);
    }
  });

  test('phone only is flagged', () {
    expect(ProfileTuning.of(const UserProfile(wearable: Wearable.phoneOnly)).phoneOnly, isTrue);
    expect(ProfileTuning.of(const UserProfile(wearable: Wearable.ring)).phoneOnly, isFalse);
  });
}
