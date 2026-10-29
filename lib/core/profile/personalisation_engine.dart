/// HUX Personalisation Engine
/// --------------------------
/// "Everything built, only what fits shown." Turns a [UserProfile] into
/// the 2–4 featured cards for the Today screen. Pure Dart, deterministic,
/// no I/O — same answers always give the same cards.
///
/// How it scores (simple on purpose — easy to explain, easy to tune):
/// - each onboarding answer adds points to the features it points at;
/// - how often the user opened a feature adds a SMALL bonus (capped), so
///   usage re-ranks cards weekly without overriding what they told us;
/// - sensitive features (cycle, family, medical) are only ever featured
///   when the user's own answers point to them;
/// - ties prefer features that already work, then catalog order.
library;

import 'feature_catalog.dart';
import 'user_profile.dart';

class PersonalisationEngine {
  static const minFeatured = 2;
  static const maxFeatured = 4;

  /// Usage can add at most this many points per feature.
  static const maxUsageBonus = 2;

  /// What an empty profile (everything skipped) sees, and what tops up
  /// a short list to [minFeatured]. Both already work today.
  static const defaults = [FeatureId.weeklyStory, FeatureId.sleepRegularity];

  const PersonalisationEngine();

  /// Points from the user's answers alone (no usage). Exposed for tests
  /// and for the Explore screen's "Recommended for you" ordering.
  Map<FeatureId, int> answerScores(UserProfile p) {
    final s = <FeatureId, int>{};
    void add(FeatureId id, int points) => s[id] = (s[id] ?? 0) + points;

    for (final goal in p.goals) {
      switch (goal) {
        case Goal.sleepBetter:
          add(FeatureId.targetBedtime, 3);
          add(FeatureId.sleepRegularity, 3);
          add(FeatureId.indianJournal, 2);
        case Goal.loseWeight:
          add(FeatureId.proteinGap, 3);
          add(FeatureId.nextStepTargets, 3);
          add(FeatureId.walkAfterMeal, 2);
        case Goal.getFit:
          add(FeatureId.effortTarget, 3);
          add(FeatureId.nextStepTargets, 2);
          add(FeatureId.streaksMonthly, 2);
          add(FeatureId.zeroTo5k, 1);
          add(FeatureId.homeWorkouts, 1);
        case Goal.lessStress:
          add(FeatureId.indianJournal, 3);
          add(FeatureId.sleepRegularity, 2);
          add(FeatureId.sitTooLong, 1);
          add(FeatureId.aiCoach, 1);
        case Goal.sugarBp:
          add(FeatureId.walkAfterMeal, 4);
          add(FeatureId.medicineReminders, 2);
          add(FeatureId.doctorReport, 2);
          add(FeatureId.beginnerWalkPlan, 1);
        case Goal.activeElder:
          add(FeatureId.beginnerWalkPlan, 4);
          add(FeatureId.medicineReminders, 2);
          add(FeatureId.walkAfterMeal, 1);
        case Goal.cycleHealth:
          add(FeatureId.cycleTracker, 4);
          add(FeatureId.homeWorkouts, 1);
      }
    }

    switch (p.dayType) {
      case DayType.desk:
        add(FeatureId.sitTooLong, 3);
        add(FeatureId.walkAfterMeal, 1);
      case DayType.nightShift:
        add(FeatureId.nightShiftMode, 5);
        add(FeatureId.targetBedtime, 1);
      case DayType.student:
        add(FeatureId.examMode, 4);
        add(FeatureId.sleepRegularity, 1);
      case DayType.homemaker:
        add(FeatureId.homeWorkouts, 2);
        add(FeatureId.walkAfterMeal, 1);
      case DayType.fieldTravel:
        add(FeatureId.airAndHeatAlerts, 3);
      case DayType.retired:
        add(FeatureId.beginnerWalkPlan, 2);
      case null:
        break;
    }

    switch (p.audience) {
      case Audience.parent:
        add(FeatureId.familyCircle, 4);
        add(FeatureId.medicineReminders, 1);
      case Audience.family:
        add(FeatureId.familyCircle, 2);
      case Audience.me:
      case null:
        break;
    }

    switch (p.fasting) {
      case FastingHabit.weekly:
      case FastingHabit.ramadan:
      case FastingHabit.navratri:
      case FastingHabit.other:
        add(FeatureId.fastingMode, 4);
      case FastingHabit.none:
      case null:
        break;
    }

    // Vegetarian diets in India commonly run short on protein.
    if (p.diet == Diet.veg || p.diet == Diet.jain || p.diet == Diet.egg) {
      add(FeatureId.proteinGap, 1);
    }

    if (p.wearable == Wearable.phoneOnly) add(FeatureId.nextStepTargets, 1);

    return s;
  }

  /// The 2–4 featured cards, best first.
  ///
  /// [opens] = how many times the user opened each feature recently
  /// (e.g. the last 7 days); missing entries count as zero.
  List<FeatureId> featuredFor(UserProfile profile, {Map<FeatureId, int> opens = const {}}) {
    final answers = answerScores(profile);

    final candidates = <({FeatureInfo info, int score})>[];
    for (final info in FeatureCatalog.all) {
      final fromAnswers = answers[info.id] ?? 0;
      // Sensitive features only when the user's own answers point there —
      // never because of a default or a usage bonus alone.
      if (info.sensitive && fromAnswers < 2) continue;
      if (fromAnswers == 0) continue;
      final usage = (opens[info.id] ?? 0).clamp(0, maxUsageBonus).toInt();
      candidates.add((info: info, score: fromAnswers + usage));
    }

    final order = {for (var i = 0; i < FeatureCatalog.all.length; i++) FeatureCatalog.all[i].id: i};
    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byAvailable = (b.info.isAvailable ? 1 : 0).compareTo(a.info.isAvailable ? 1 : 0);
      if (byAvailable != 0) return byAvailable;
      return order[a.info.id]!.compareTo(order[b.info.id]!);
    });

    final picked = candidates.take(maxFeatured).map((c) => c.info.id).toList();
    for (final d in defaults) {
      if (picked.length >= minFeatured) break;
      if (!picked.contains(d)) picked.add(d);
    }
    return picked;
  }
}
