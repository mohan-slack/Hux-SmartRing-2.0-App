/// The app's top-level shell: bottom navigation across Today, Trends,
/// Story, and Modes. The demo banner is pinned here, above all four
/// tabs — a single, unmissable element rather than four copies that
/// could drift out of sync. Each tab keeps its own state when you
/// switch away and back (IndexedStack builds every tab once and keeps
/// them alive, rather than disposing and rebuilding on every switch).
///
/// Liquid-glass notes: the dark stage ([HuxBackground]) is painted
/// ONCE here behind everything; screens never paint their own. The nav
/// bar is the app's ONE real BackdropFilter — `extendBody: true` lets
/// tab content scroll behind it, so the blur has something genuine to
/// refract (see hux_glass.dart for why panels elsewhere fake it).

import 'package:flutter/material.dart';

import '../core/auth/auth_service.dart';
import '../core/environment/environment_service.dart';
import '../core/food/food_log_service.dart';
import '../core/coach/coach_context.dart';
import '../core/coach/coach_service.dart';
import '../core/food/meal_analyzer.dart';
import '../core/home/home_extras.dart';
import '../core/legal/privacy_service.dart';
import '../core/nudges/nudge_service.dart';
import '../core/plans/plan_library.dart';
import '../core/plans/plan_progress.dart';
import '../core/plans/speaker.dart';
import '../core/plans/voice_cues.dart';
import '../core/progress/progress_service.dart';
import '../core/journal/journal.dart';
import '../core/meaning/readout_service.dart';
import '../core/meaning/weekly_story.dart';
import '../core/modes/mode_service.dart';
import '../core/profile/feature_catalog.dart';
import '../core/profile/profile_service.dart';
import '../core/profile/user_profile.dart';
import '../core/ring/data_source.dart';
import '../core/storage/health_store.dart';
import '../core/sync/sync_service.dart';
import '../theme/hux_glass.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';
import 'hubs/plans_hub.dart';
import 'hubs/progress_hub.dart';
import 'air_heat_screen.dart';
import 'briefing_screen.dart';
import 'coach/coach_screen.dart';
import 'legal/privacy_account_screen.dart';
import 'food/food_screen.dart';
import 'for_you.dart';
import 'journal_screen.dart';
import 'plans/plans_screen.dart';
import 'sit_nudge_screen.dart';
import 'walk_nudge_screen.dart';
import 'modes_screen.dart';
import 'onboarding/onboarding_screen.dart';
import 'today_screen.dart';

class AppShell extends StatefulWidget {
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;
  final WeeklyStoryService storyService;
  final ModeService modeService;

  /// Which [RingAdapter] the composition root wired up — decides the
  /// banner's text and color. Defaults to [RingDataSource.mock] so
  /// every existing caller/test that predates this field is unaffected.
  final RingDataSource dataSource;

  /// Optional so every existing caller/test that predates sign-in stays
  /// unaffected — when null, the banner simply has no sign-out icon
  /// (there's no `app.dart`-level auth gate to return to).
  final AuthService? authService;

  /// Optional, like [authService]: without it there's no "For you"
  /// section and no Explore screen (every pre-personalisation test).
  final ProfileService? profileService;

  /// Photo meal analysis; null = photo logging shows "coming soon".
  final MealAnalyzer? mealAnalyzer;

  /// Backend call for the coach; null = coach shows "not set up".
  final FunctionInvoker? coachInvoke;

  /// Called after "Delete data on this phone" so first-run screens
  /// (privacy notice, questions) show again.
  final VoidCallback? onLocalDataDeleted;

  /// Reminders; null = nudge features show "coming soon".
  final NudgeService? nudgeService;

  /// Air & heat outlooks; null = "coming soon".
  final EnvironmentService? environmentService;

  /// Home syncs on open/resume (see TodayScreen.autoSync). The app
  /// turns this on; widget tests leave it off.
  final bool autoSync;

  const AppShell({
    super.key,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.storyService,
    required this.modeService,
    this.dataSource = RingDataSource.mock,
    this.authService,
    this.profileService,
    this.mealAnalyzer,
    this.coachInvoke,
    this.onLocalDataDeleted,
    this.nudgeService,
    this.environmentService,
    this.autoSync = false,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  late final JournalService _journal = JournalService(widget.store);
  late final FoodLogService _foodLog = FoodLogService(widget.store);
  late final PlanProgressService _plans = PlanProgressService(widget.store);
  late final ProgressService _progress = ProgressService(widget.store);
  late final HomeExtrasLoader _homeExtras = HomeExtrasLoader(
    store: widget.store,
    foodLog: _foodLog,
    nudges: widget.nudgeService,
    environment: widget.environmentService,
    plans: _plans,
    journal: _journal,
  );
  late final PrivacyService _privacy = PrivacyService(
    widget.store,
    auth: widget.authService,
    stopReminders: widget.nudgeService?.cancelAll,
  );
  late final CoachService _coach = CoachService(
    widget.store,
    invoke: widget.coachInvoke,
    loadContext: CoachContextLoader(
      store: widget.store,
      readouts: widget.readoutService,
      profiles: widget.profileService,
    ).load,
  );

  /// IndexedStack keeps Today's State alive when you switch away —
  /// that's the point, tab state survives. But it also means Today
  /// never re-reads the store on its own if something changed it
  /// elsewhere (e.g. starting a mode from the Modes tab). Ping this
  /// every time Today becomes the visible tab so it refreshes instead
  /// of silently showing what it looked like when it was last built.
  final _todayRefresh = ValueNotifier<int>(0);

  /// Pinged when the Coach / Progress tabs become visible again, so
  /// IndexedStack-kept screens don't go stale.
  final _coachRefresh = ValueNotifier<int>(0);
  final _progressRefresh = ValueNotifier<int>(0);

  /// Which part of the Progress tab is showing (Trends / Story / Streaks).
  final _progressSection = ValueNotifier<ProgressSection>(ProgressSection.trends);

  static const _homeTab = 0;
  static const _coachTab = 1;
  static const _progressTab = 3;

  @override
  void dispose() {
    _todayRefresh.dispose();
    _coachRefresh.dispose();
    _progressRefresh.dispose();
    _progressSection.dispose();
    super.dispose();
  }

  /// First word of the email's name part, e.g. "mohan.r@…" → "Mohan".
  String? get _firstName {
    final email = widget.authService?.currentUser?.email;
    if (email == null || !email.contains('@')) return null;
    final word = RegExp(r'[A-Za-z]+').firstMatch(email.split('@').first)?.group(0);
    if (word == null || word.length < 2 || word.length > 12) return null;
    return word[0].toUpperCase() + word.substring(1).toLowerCase();
  }

  void _onDestinationSelected(int index) {
    final changed = index != _index;
    setState(() => _index = index);
    if (index == 0) _todayRefresh.value++;
    if (changed && index == _coachTab) _coachRefresh.value++;
    if (changed && index == _progressTab) _progressRefresh.value++;
  }

  /// Opens Life modes (no longer a tab: it lives under Plans).
  Future<void> _openModes() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Life modes')),
        body: ModesScreen(modeService: widget.modeService),
      ),
    ));
    _todayRefresh.value++; // a started/ended mode changes Home
  }

  void _showProgress(ProgressSection section) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _progressSection.value = section;
    _onDestinationSelected(_progressTab);
  }

  /// Opens a feature, then refreshes Home (a meal, journal entry or plan
  /// session logged there changes the agenda and food card).
  Future<void> _openFeature(FeatureId id) async {
    await _openFeatureInner(id);
    _todayRefresh.value++;
  }

  Future<void> _openFeatureInner(FeatureId id) async {
    final profiles = widget.profileService;
    try {
      await profiles?.recordOpen(id);
    } catch (_) {
      // Usage counts only re-rank cards; never block opening a feature.
    }
    if (!mounted) return;

    final info = FeatureCatalog.of(id);
    if (!info.isAvailable) {
      final voted = (await profiles?.votedFeatures())?.contains(id) ?? false;
      if (!mounted) return;
      await showComingSoonSheet(
        context,
        info: info,
        alreadyVoted: voted,
        onVote: () async {
          await profiles?.vote(id);
        },
      );
      return;
    }

    // Features with their own screen open it on top.
    if (id == FeatureId.indianJournal) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => JournalScreen(journal: _journal),
      ));
      return;
    }
    if (id == FeatureId.aiCoach) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      _onDestinationSelected(_coachTab);
      return;
    }
    if (id == FeatureId.streaksMonthly) {
      _showProgress(ProgressSection.streaks);
      return;
    }
    if (id == FeatureId.sleepRegularity) {
      _showProgress(ProgressSection.trends);
      return;
    }
    if (id == FeatureId.weeklyStory) {
      _showProgress(ProgressSection.story);
      return;
    }
    if (id == FeatureId.shaadiMode ||
        id == FeatureId.examMode ||
        id == FeatureId.nightShiftMode ||
        id == FeatureId.fastingMode) {
      await _openModes();
      return;
    }
    if (id == FeatureId.airAndHeatAlerts && widget.environmentService != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AirHeatScreen(env: widget.environmentService!),
      ));
      return;
    }
    if (id == FeatureId.beginnerWalkPlan || id == FeatureId.zeroTo5k) {
      final profile = await profiles?.loadProfile();
      final goals = profile?.goals ?? const <Goal>[];
      final recommended = recommendedPlanIds(
        elder: goals.contains(Goal.activeElder) ||
            profile?.dayType == DayType.retired ||
            profile?.audience == Audience.parent,
        fitGoal: goals.contains(Goal.getFit) || id == FeatureId.zeroTo5k,
        weightOrSugar: goals.contains(Goal.loseWeight) || goals.contains(Goal.sugarBp),
        desk: profile?.dayType == DayType.desk,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlansScreen(
          progress: _plans,
          recommended: recommended,
          language: CueLanguageTts.fromProfile(profile?.language),
          speakerFactory: TtsSpeaker.new,
        ),
      ));
      return;
    }
    if (id == FeatureId.sitTooLong && widget.nudgeService != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => SitNudgeScreen(nudges: widget.nudgeService!),
      ));
      return;
    }
    if (id == FeatureId.walkAfterMeal && widget.nudgeService != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WalkNudgeScreen(nudges: widget.nudgeService!),
      ));
      return;
    }
    if (id == FeatureId.proteinGap) {
      final diet = (await profiles?.loadProfile())?.diet;
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => FoodScreen(
          foodLog: _foodLog,
          analyzer: widget.mealAnalyzer,
          diet: diet,
          onMealLogged: widget.nudgeService == null
              ? null
              : (meal) => widget.nudgeService!.onMealLogged(meal.loggedAt.toLocal()),
        ),
      ));
      return;
    }

    // Anything else lives on Home.
    Navigator.of(context).popUntil((route) => route.isFirst);
    _onDestinationSelected(_homeTab);
  }

  Future<void> _editAnswers() async {
    final profiles = widget.profileService;
    if (profiles == null) return;
    final current = await profiles.loadProfile() ?? const UserProfile();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (routeContext) => OnboardingScreen(
        initial: current,
        onDone: (profile) async {
          await profiles.saveProfile(profile);
          if (routeContext.mounted) Navigator.of(routeContext).pop();
        },
      ),
    ));
    // Featured cards depend on the answers: refresh Today.
    _todayRefresh.value++;
  }

  Future<void> _openPrivacy() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PrivacyAccountScreen(
        privacy: _privacy,
        coach: _coach,
        foodLog: _foodLog,
        onLocalDataDeleted: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          widget.onLocalDataDeleted?.call();
        },
      ),
    ));
  }

  void _openExplore() {
    final profiles = widget.profileService;
    if (profiles == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ExploreScreen(
        profileService: profiles,
        onOpen: _openFeature,
        onEditAnswers: _editAnswers,
      ),
    ));
  }

  // ---- sheets ------------------------------------------------------------

  /// The "+" button: quick ways to log or start something.
  Future<void> _openQuickLog() async {
    final picked = await showModalBottomSheet<FeatureId>(
      context: context,
      showDragHandle: true,
      builder: (c) {
        Widget tile(FeatureId id, IconData icon, Color color, String title, String sub) => ListTile(
              leading: HuxIconBadge(icon: icon, color: color),
              title: Text(title),
              subtitle: Text(sub),
              onTap: () => Navigator.pop(c, id),
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile(FeatureId.proteinGap, Icons.restaurant_rounded, HuxColors.ringFood, 'Log a meal',
                  'Type it or snap a photo'),
              tile(FeatureId.indianJournal, Icons.edit_note_rounded, HuxColors.ringHabit, 'Journal today',
                  'Chai, late dinner, sweets…'),
              tile(FeatureId.beginnerWalkPlan, Icons.directions_walk_rounded, HuxColors.ringSteps, 'Walking plans',
                  'Pick a guided session with voice cues'),
              tile(FeatureId.aiCoach, Icons.auto_awesome, HuxColors.ringCharge, 'Ask the coach',
                  'Anything about sleep, energy or food'),
              const SizedBox(height: HuxSpacing.sm),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) await _openFeature(picked);
  }

  /// The avatar on Home: account, privacy, answers, all features, sign out.
  Future<void> _openMe() async {
    final email = widget.authService?.currentUser?.email;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (email != null)
              ListTile(
                leading: HuxAvatar(initial: (_firstName ?? 'H')[0]),
                title: Text(_firstName ?? 'Your account'),
                subtitle: Text(email),
              ),
            const Divider(height: 1),
            if (widget.nudgeService != null)
              ListTile(
                leading: const Icon(Icons.wb_sunny_outlined),
                title: const Text('Morning briefing'),
                onTap: () => Navigator.pop(c, 'briefing'),
              ),
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacy & account'),
              onTap: () => Navigator.pop(c, 'privacy'),
            ),
            if (widget.profileService != null) ...[
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Edit my answers'),
                onTap: () => Navigator.pop(c, 'answers'),
              ),
              ListTile(
                leading: const Icon(Icons.apps_rounded),
                title: const Text('All features'),
                onTap: () => Navigator.pop(c, 'explore'),
              ),
            ],
            if (widget.authService != null)
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: HuxColors.rundown),
                title: const Text('Sign out', style: TextStyle(color: HuxColors.rundown)),
                onTap: () => Navigator.pop(c, 'signout'),
              ),
            const SizedBox(height: HuxSpacing.sm),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'briefing':
        await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => BriefingScreen(nudges: widget.nudgeService!),
        ));
      case 'privacy':
        await _openPrivacy();
      case 'answers':
        await _editAnswers();
      case 'explore':
        _openExplore();
      case 'signout':
        try {
          await widget.authService?.signOut();
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasProfiles = widget.profileService != null;
    return Scaffold(
      // Content scrolls behind the floating nav bar; each tab's scrollable
      // adds HuxGlass.navClearance of bottom padding.
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const HuxBackground(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Only demo / unofficial-ring builds show a source strip.
                if (widget.dataSource != RingDataSource.health) _SourceBanner(source: widget.dataSource),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: [
                      for (final (i, tab) in [
                      TodayScreen(
                        store: widget.store,
                        syncService: widget.syncService,
                        readoutService: widget.readoutService,
                        modeService: widget.modeService,
                        refreshSignal: _todayRefresh,
                        profileService: widget.profileService,
                        onOpenFeature: hasProfiles ? _openFeature : null,
                        onSeeAllFeatures: hasProfiles ? _openExplore : null,
                        greetingName: _firstName,
                        onOpenProfile: _openMe,
                        onAsk: () => _onDestinationSelected(_coachTab),
                        extrasLoader: _homeExtras.load,
                        autoSync: widget.autoSync,
                      ),
                      CoachScreen(
                        coach: _coach,
                        embedded: true,
                        refreshSignal: _coachRefresh,
                        onNotNow: () => _onDestinationSelected(0),
                      ),
                      PlansHub(
                        onOpenFeature: _openFeature,
                        onOpenModes: _openModes,
                        onSeeAll: hasProfiles ? _openExplore : null,
                      ),
                      ProgressHub(
                        store: widget.store,
                        storyService: widget.storyService,
                        progress: _progress,
                        section: _progressSection,
                        refreshSignal: _progressRefresh,
                      ),
                      ].indexed)
                        // Hidden tabs keep their state but stop animating
                        // (spinners, typing dots) — saves battery and
                        // lets widget tests settle.
                        TickerMode(enabled: i == _index, child: tab),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: HuxPillNavBar(
        index: _index,
        onSelect: _onDestinationSelected,
        onPlus: _openQuickLog,
        items: const [
          HuxNavItem(Icons.home_outlined, Icons.home_rounded, 'Home'),
          HuxNavItem(Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Coach'),
          HuxNavItem(Icons.event_note_outlined, Icons.event_note_rounded, 'Plans'),
          HuxNavItem(Icons.insights_outlined, Icons.insights_rounded, 'Progress'),
        ],
      ),
    );
  }
}

/// Unmissable — screenshots of this build must never be mistaken for
/// real ring data, on any tab. Text and color both follow [source]
/// truthfully: mock stays the original amber "DEMO" banner; the
/// health-app source shows no banner in v1 (see AppShell).
class _SourceBanner extends StatelessWidget {
  final RingDataSource source;

  const _SourceBanner({required this.source});

  Color get _background => switch (source) {
        RingDataSource.mock => HuxColors.demoAmber,
        RingDataSource.health => HuxColors.devBlueGrey,
      };

  // Amber is light: dark ink. Blue-grey and purple are dark: white text.
  Color get _foreground => switch (source) {
        RingDataSource.mock => HuxColors.ink,
        RingDataSource.health => HuxColors.onVivid,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: _background,
      padding: const EdgeInsets.symmetric(vertical: HuxSpacing.xs, horizontal: HuxSpacing.lg),
      child: Text(
        source.bannerText,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700, color: _foreground),
      ),
    );
  }
}
