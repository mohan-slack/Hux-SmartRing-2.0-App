/// Personalisation engine: answers -> 2-4 featured cards.
/// Run with: flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/profile/feature_catalog.dart';
import 'package:hux_app/core/profile/personalisation_engine.dart';
import 'package:hux_app/core/profile/user_profile.dart';

void main() {
  const engine = PersonalisationEngine();

  void expectSize(List<FeatureId> featured) {
    expect(featured.length, inInclusiveRange(2, 4));
    expect(featured.toSet().length, featured.length, reason: 'no duplicates');
  }

  test('everything skipped -> the working defaults', () {
    final featured = engine.featuredFor(const UserProfile());
    expect(featured, PersonalisationEngine.defaults);
  });

  test('desk job + less stress -> sit-too-long and journal lead', () {
    final featured = engine.featuredFor(const UserProfile(
      dayType: DayType.desk,
      goals: [Goal.lessStress],
    ));
    expectSize(featured);
    expect(featured, containsAll([FeatureId.sitTooLong, FeatureId.indianJournal]));
  });

  test('night shift -> night shift mode is the top card', () {
    final featured = engine.featuredFor(const UserProfile(dayType: DayType.nightShift));
    expectSize(featured);
    expect(featured.first, FeatureId.nightShiftMode);
  });

  test('student -> exam mode is featured', () {
    final featured = engine.featuredFor(const UserProfile(dayType: DayType.student));
    expect(featured, contains(FeatureId.examMode));
  });

  test('fasting answer -> fasting companion is featured', () {
    final featured = engine.featuredFor(const UserProfile(fasting: FastingHabit.navratri));
    expect(featured, contains(FeatureId.fastingMode));
  });

  test('sugar/BP goal -> walk after meals leads', () {
    final featured = engine.featuredFor(const UserProfile(goals: [Goal.sugarBp]));
    expectSize(featured);
    expect(featured.first, FeatureId.walkAfterMeal);
  });

  test('sensitive features never appear without the user pointing at them', () {
    final profiles = [
      const UserProfile(),
      const UserProfile(dayType: DayType.desk, goals: [Goal.getFit]),
      const UserProfile(goals: [Goal.loseWeight], diet: Diet.veg),
    ];
    final sensitive = FeatureCatalog.all.where((f) => f.sensitive).map((f) => f.id).toSet();
    for (final p in profiles) {
      // Even heavy usage of a sensitive feature can't feature it alone.
      final opens = {for (final id in sensitive) id: 50};
      final featured = engine.featuredFor(p, opens: opens);
      expect(featured.toSet().intersection(sensitive), isEmpty);
    }
  });

  test('cycle health goal -> cycle tracker is featured', () {
    final featured = engine.featuredFor(const UserProfile(goals: [Goal.cycleHealth]));
    expect(featured, contains(FeatureId.cycleTracker));
  });

  test('usage re-ranks within the answers, but is capped', () {
    const p = UserProfile(goals: [Goal.loseWeight]);
    final before = engine.featuredFor(p);
    expect(before.first, isNot(FeatureId.walkAfterMeal));

    final after = engine.featuredFor(p, opens: {FeatureId.walkAfterMeal: 100});
    expect(after.first, FeatureId.walkAfterMeal);
  });

  test('usage alone never adds a feature the answers did not point to', () {
    final featured = engine.featuredFor(
      const UserProfile(dayType: DayType.student),
      opens: {FeatureId.zeroTo5k: 100},
    );
    expect(featured, isNot(contains(FeatureId.zeroTo5k)));
  });

  test('same answers always give the same cards (deterministic)', () {
    const p = UserProfile(goals: [Goal.getFit, Goal.sleepBetter], dayType: DayType.desk);
    expect(engine.featuredFor(p), engine.featuredFor(p));
  });

  test('every profile combination yields 2-4 cards', () {
    for (final day in [null, ...DayType.values]) {
      for (final goal in [null, ...Goal.values]) {
        final featured = engine.featuredFor(UserProfile(
          dayType: day,
          goals: goal == null ? const [] : [goal],
        ));
        expectSize(featured);
      }
    }
  });

  test('profile JSON round-trips and tolerates unknown values', () {
    const p = UserProfile(
      audience: Audience.parent,
      goals: [Goal.sugarBp, Goal.activeElder],
      dayType: DayType.retired,
      diet: Diet.veg,
      fasting: FastingHabit.weekly,
      wearable: Wearable.phoneOnly,
      coachStyle: CoachStyle.amma,
      language: AppLanguage.telugu,
    );
    final back = UserProfile.fromJson(p.toJson());
    expect(back.toJson(), p.toJson());

    final odd = UserProfile.fromJson({
      'goals': ['sleepBetter', 'flyToMoon', 'getFit', 'lessStress'],
      'dayType': 'astronaut',
    });
    expect(odd.goals, [Goal.sleepBetter, Goal.getFit]);
    expect(odd.dayType, isNull);
  });
}
