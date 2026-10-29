/// HUX Feature Catalog
/// -------------------
/// Every feature the app has or plans, in ONE list. The personalisation
/// engine picks 2–4 of these for the Today screen; the Explore screen
/// shows all of them. Adding a feature = adding one entry here.
///
/// [FeatureStatus.comingSoon] entries are real plans (see the Confluence
/// "Competitor Research, Innovation & Personalised Version Plan" page),
/// shown honestly as "Coming soon" — never as if they already work.
library;

enum FeatureStatus { available, comingSoon }

enum FeatureCategory { recovery, sleep, activity, food, mind, family, modes }

extension FeatureCategoryLabel on FeatureCategory {
  String get label => switch (this) {
        FeatureCategory.recovery => 'Recovery',
        FeatureCategory.sleep => 'Sleep',
        FeatureCategory.activity => 'Activity',
        FeatureCategory.food => 'Food',
        FeatureCategory.mind => 'Mind & habits',
        FeatureCategory.family => 'Family',
        FeatureCategory.modes => 'Life modes',
      };
}

enum FeatureId {
  // Available now (built on what the app already does).
  sleepRegularity,
  weeklyStory,
  shaadiMode,
  examMode,
  nightShiftMode,
  fastingMode,

  // Built on HUX Charge (shown in the Today header).
  effortTarget,
  targetBedtime,
  indianJournal,
  nextStepTargets,
  proteinGap,
  walkAfterMeal,
  airAndHeatAlerts,
  sitTooLong,
  beginnerWalkPlan,
  zeroTo5k,

  // Version 1 plan.
  streaksMonthly,
  aiCoach,

  // Version 2 plan.
  familyCircle,
  medicineReminders,
  cycleTracker,
  doctorReport,
  homeWorkouts,
}

class FeatureInfo {
  final FeatureId id;
  final String title;

  /// One plain sentence: what it does for the user.
  final String blurb;
  final FeatureCategory category;
  final FeatureStatus status;

  /// Health-sensitive (cycle, family monitoring, medical): never shown
  /// as a featured card unless the user's own answers point to it, and
  /// will need explicit consent when built.
  final bool sensitive;

  const FeatureInfo({
    required this.id,
    required this.title,
    required this.blurb,
    required this.category,
    required this.status,
    this.sensitive = false,
  });

  bool get isAvailable => status == FeatureStatus.available;
}

const _all = <FeatureInfo>[
  // ---- available now ----
  FeatureInfo(
    id: FeatureId.sleepRegularity,
    title: 'Sleep vs your normal',
    blurb: 'Your nights compared with your own usual — see Trends.',
    category: FeatureCategory.sleep,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.weeklyStory,
    title: 'Weekly body story',
    blurb: 'This week vs last week, and one thing to try next.',
    category: FeatureCategory.recovery,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.shaadiMode,
    title: 'Shaadi / Big day mode',
    blurb: 'Plan your energy for a wedding or big event.',
    category: FeatureCategory.modes,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.examMode,
    title: 'Exam season mode',
    blurb: 'Sleep and focus plan for exam weeks.',
    category: FeatureCategory.modes,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.nightShiftMode,
    title: 'Night shift mode',
    blurb: 'Readouts that understand day-time sleep.',
    category: FeatureCategory.modes,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.fastingMode,
    title: 'Fasting companion',
    blurb: 'Roza, Navratri, Ekadashi and more — food and rest tips.',
    category: FeatureCategory.modes,
    status: FeatureStatus.available,
  ),

  // ---- version 1 plan ----
  FeatureInfo(
    id: FeatureId.effortTarget,
    title: "Today's effort",
    blurb: 'How hard to go today, based on your recovery.',
    category: FeatureCategory.recovery,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.targetBedtime,
    title: 'Target bedtime',
    blurb: 'When to sleep tonight to recover well.',
    category: FeatureCategory.sleep,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.indianJournal,
    title: 'Daily journal',
    blurb: 'Chai, late dinner, sweets, travel — see what they do to your sleep.',
    category: FeatureCategory.mind,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.nextStepTargets,
    title: 'Next-step targets',
    blurb: 'A small, doable goal for today, a little above yesterday.',
    category: FeatureCategory.activity,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.proteinGap,
    title: 'Protein gap',
    blurb: 'What to add today, in katoris — "1 katori dal + paneer".',
    category: FeatureCategory.food,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.walkAfterMeal,
    title: 'Walk after meals',
    blurb: 'A 10-minute walk nudge after lunch and dinner.',
    category: FeatureCategory.activity,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.airAndHeatAlerts,
    title: 'Air & heat alerts',
    blurb: 'Bad AQI or heatwave? Move your workout indoors.',
    category: FeatureCategory.activity,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.sitTooLong,
    title: 'Sit-too-long nudge',
    blurb: 'A stretch reminder after long desk hours.',
    category: FeatureCategory.activity,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.beginnerWalkPlan,
    title: 'Guided walking plans',
    blurb: 'First Steps, Brisk 100, Japanese interval walking, Steady & Strong 60+ — with voice cues.',
    category: FeatureCategory.activity,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.zeroTo5k,
    title: 'Zero to 5K',
    blurb: 'Walk-run to 30 minutes of running — plus stair snacks for busy days.',
    category: FeatureCategory.activity,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.streaksMonthly,
    title: 'Streaks & monthly report',
    blurb: 'A forgiving streak with rest passes, and your month at a glance.',
    category: FeatureCategory.mind,
    status: FeatureStatus.available,
  ),
  FeatureInfo(
    id: FeatureId.aiCoach,
    title: 'HUX coach chat',
    blurb: 'Ask anything about your body, in your style and language.',
    category: FeatureCategory.mind,
    status: FeatureStatus.available,
  ),

  // ---- version 2 plan ----
  FeatureInfo(
    id: FeatureId.familyCircle,
    title: 'Family circle',
    blurb: "See a parent's daily status, with their consent.",
    category: FeatureCategory.family,
    status: FeatureStatus.comingSoon,
    sensitive: true,
  ),
  FeatureInfo(
    id: FeatureId.medicineReminders,
    title: 'Medicine reminders',
    blurb: 'Simple daily reminders, large text.',
    category: FeatureCategory.family,
    status: FeatureStatus.comingSoon,
    sensitive: true,
  ),
  FeatureInfo(
    id: FeatureId.cycleTracker,
    title: 'Cycle tracker',
    blurb: 'Energy and workout tips by cycle phase.',
    category: FeatureCategory.recovery,
    status: FeatureStatus.comingSoon,
    sensitive: true,
  ),
  FeatureInfo(
    id: FeatureId.doctorReport,
    title: 'Doctor report',
    blurb: '30 days of data as a PDF to share with your doctor.',
    category: FeatureCategory.recovery,
    status: FeatureStatus.comingSoon,
    sensitive: true,
  ),
  FeatureInfo(
    id: FeatureId.homeWorkouts,
    title: 'Home workouts',
    blurb: 'Yoga, Surya Namaskar and 1BHK-friendly workouts.',
    category: FeatureCategory.activity,
    status: FeatureStatus.comingSoon,
  ),
];

class FeatureCatalog {
  const FeatureCatalog._();

  static List<FeatureInfo> get all => _all;

  static FeatureInfo of(FeatureId id) => _all.firstWhere((f) => f.id == id);
}
