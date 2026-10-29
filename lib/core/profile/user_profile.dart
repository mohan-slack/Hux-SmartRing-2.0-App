/// HUX User Profile
/// ----------------
/// The answers to the short onboarding questions (see
/// screens/onboarding/onboarding_screen.dart). Pure Dart, no I/O.
///
/// Every answer is optional: the user can skip any question (or all of
/// them) and the app still works — the personalisation engine falls back
/// to sensible defaults. Nothing here is a medical fact about the user;
/// "keep sugar or BP in check" is a stated GOAL, never a diagnosis.
library;

enum Audience { me, parent, family }

enum Goal { sleepBetter, loseWeight, getFit, lessStress, sugarBp, activeElder, cycleHealth }

enum DayType { desk, nightShift, student, homemaker, fieldTravel, retired }

enum Diet { veg, egg, nonVeg, jain }

enum FastingHabit { none, weekly, ramadan, navratri, other }

enum Wearable { phoneOnly, watch, band, ring }

enum CoachStyle { coach, dost, amma, numbers }

enum AppLanguage { english, hinglish, telugu, hindi, tamil, kannada }

/// Short, user-facing labels — what the onboarding chips show.
extension AudienceLabel on Audience {
  String get label => switch (this) {
        Audience.me => 'Me',
        Audience.parent => 'My parent',
        Audience.family => 'Family',
      };
}

extension GoalLabel on Goal {
  String get label => switch (this) {
        Goal.sleepBetter => 'Sleep better',
        Goal.loseWeight => 'Lose weight',
        Goal.getFit => 'Get fit or strong',
        Goal.lessStress => 'Less stress',
        Goal.sugarBp => 'Keep sugar or BP in check',
        Goal.activeElder => 'Stay active (60+)',
        Goal.cycleHealth => 'Cycle health',
      };
}

extension DayTypeLabel on DayType {
  String get label => switch (this) {
        DayType.desk => 'Desk job',
        DayType.nightShift => 'Night shift',
        DayType.student => 'Student',
        DayType.homemaker => 'Homemaker',
        DayType.fieldTravel => 'Field or travel job',
        DayType.retired => 'Retired',
      };
}

extension DietLabel on Diet {
  String get label => switch (this) {
        Diet.veg => 'Veg',
        Diet.egg => 'Egg',
        Diet.nonVeg => 'Non-veg',
        Diet.jain => 'Jain',
      };
}

extension FastingHabitLabel on FastingHabit {
  String get label => switch (this) {
        FastingHabit.none => "Don't fast",
        FastingHabit.weekly => 'Weekly fast',
        FastingHabit.ramadan => 'Ramadan',
        FastingHabit.navratri => 'Navratri',
        FastingHabit.other => 'Other fasts',
      };
}

extension WearableLabel on Wearable {
  String get label => switch (this) {
        Wearable.phoneOnly => 'Phone only',
        Wearable.watch => 'Watch',
        Wearable.band => 'Band',
        Wearable.ring => 'Ring',
      };
}

extension CoachStyleLabel on CoachStyle {
  String get label => switch (this) {
        CoachStyle.coach => 'Coach — straight talk',
        CoachStyle.dost => 'Dost — friendly',
        CoachStyle.amma => 'Amma — caring',
        CoachStyle.numbers => 'Just the numbers',
      };
}

extension AppLanguageLabel on AppLanguage {
  String get label => switch (this) {
        AppLanguage.english => 'English',
        AppLanguage.hinglish => 'Hinglish',
        AppLanguage.telugu => 'తెలుగు',
        AppLanguage.hindi => 'हिन्दी',
        AppLanguage.tamil => 'தமிழ்',
        AppLanguage.kannada => 'ಕನ್ನಡ',
      };
}

class UserProfile {
  /// Most users pick ONE goal; the UI allows up to [maxGoals].
  static const maxGoals = 2;

  final Audience? audience;
  final List<Goal> goals;
  final DayType? dayType;
  final Diet? diet;
  final FastingHabit? fasting;
  final Wearable? wearable;
  final CoachStyle? coachStyle;
  final AppLanguage? language;

  const UserProfile({
    this.audience,
    this.goals = const [],
    this.dayType,
    this.diet,
    this.fasting,
    this.wearable,
    this.coachStyle,
    this.language,
  });

  /// True when the user skipped everything — still a valid profile.
  bool get isEmpty =>
      audience == null &&
      goals.isEmpty &&
      dayType == null &&
      diet == null &&
      fasting == null &&
      wearable == null &&
      coachStyle == null &&
      language == null;

  UserProfile copyWith({
    Audience? audience,
    List<Goal>? goals,
    DayType? dayType,
    Diet? diet,
    FastingHabit? fasting,
    Wearable? wearable,
    CoachStyle? coachStyle,
    AppLanguage? language,
  }) =>
      UserProfile(
        audience: audience ?? this.audience,
        goals: goals ?? this.goals,
        dayType: dayType ?? this.dayType,
        diet: diet ?? this.diet,
        fasting: fasting ?? this.fasting,
        wearable: wearable ?? this.wearable,
        coachStyle: coachStyle ?? this.coachStyle,
        language: language ?? this.language,
      );

  Map<String, Object?> toJson() => {
        'v': 1,
        'audience': audience?.name,
        'goals': goals.map((g) => g.name).toList(),
        'dayType': dayType?.name,
        'diet': diet?.name,
        'fasting': fasting?.name,
        'wearable': wearable?.name,
        'coachStyle': coachStyle?.name,
        'language': language?.name,
      };

  /// Tolerant of unknown/removed enum values (an older or newer app
  /// version wrote them): those answers just read back as "skipped".
  factory UserProfile.fromJson(Map<String, Object?> json) {
    T? pick<T extends Enum>(List<T> values, Object? raw) {
      if (raw is! String) return null;
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return null;
    }

    final rawGoals = json['goals'];
    final goals = <Goal>[
      if (rawGoals is List)
        for (final g in rawGoals)
          if (pick(Goal.values, g) case final Goal goal) goal,
    ];

    return UserProfile(
      audience: pick(Audience.values, json['audience']),
      goals: goals.take(maxGoals).toList(),
      dayType: pick(DayType.values, json['dayType']),
      diet: pick(Diet.values, json['diet']),
      fasting: pick(FastingHabit.values, json['fasting']),
      wearable: pick(Wearable.values, json['wearable']),
      coachStyle: pick(CoachStyle.values, json['coachStyle']),
      language: pick(AppLanguage.values, json['language']),
    );
  }
}
