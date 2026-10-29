/// The HUX app widget. Takes its object graph via constructor injection
/// from the composition root (main.dart) — this file never constructs
/// a RingAdapter, HealthStore, or service itself.

import 'package:flutter/material.dart';

import 'core/auth/auth_models.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/local_data_guard.dart';
import 'core/environment/environment_service.dart';
import 'core/coach/coach_service.dart';
import 'core/food/meal_analyzer.dart';
import 'core/legal/privacy_service.dart';
import 'core/nudges/nudge_service.dart';
import 'core/meaning/readout_service.dart';
import 'core/meaning/weekly_story.dart';
import 'core/modes/mode_service.dart';
import 'core/profile/profile_service.dart';
import 'core/ring/data_source.dart';
import 'core/storage/health_store.dart';
import 'core/sync/sync_service.dart';
import 'screens/app_shell.dart';
import 'screens/auth/welcome_screen.dart';
import 'screens/legal/privacy_consent_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'theme/hux_theme.dart';

class HuxApp extends StatelessWidget {
  final AuthService authService;
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;
  final WeeklyStoryService storyService;
  final ModeService modeService;
  final RingDataSource dataSource;
  final ProfileService? profileService;
  final MealAnalyzer? mealAnalyzer;

  /// Backend call for the coach; null = coach shows "not set up".
  final FunctionInvoker? coachInvoke;
  final NudgeService? nudgeService;
  final EnvironmentService? environmentService;

  const HuxApp({
    super.key,
    required this.authService,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.storyService,
    required this.modeService,
    this.dataSource = RingDataSource.mock,
    this.profileService,
    this.mealAnalyzer,
    this.coachInvoke,
    this.nudgeService,
    this.environmentService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HUX',
      debugShowCheckedModeBanner: false,
      theme: buildHuxTheme(),
      home: _AuthGate(
        authService: authService,
        store: store,
        syncService: syncService,
        readoutService: readoutService,
        storyService: storyService,
        modeService: modeService,
        dataSource: dataSource,
        profileService: profileService,
        mealAnalyzer: mealAnalyzer,
        coachInvoke: coachInvoke,
        nudgeService: nudgeService,
        environmentService: environmentService,
      ),
    );
  }
}

/// The one place "is anyone signed in" decides which screen the app
/// shows — everything else (AppShell and below) is built assuming a
/// session already exists. `authStateChanges` fires immediately with
/// the current user on first listen, so this never shows a spurious
/// flash of the login screen before Supabase has had a chance to
/// restore a persisted session.
class _AuthGate extends StatelessWidget {
  final AuthService authService;
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;
  final WeeklyStoryService storyService;
  final ModeService modeService;
  final RingDataSource dataSource;
  final ProfileService? profileService;
  final MealAnalyzer? mealAnalyzer;

  /// Backend call for the coach; null = coach shows "not set up".
  final FunctionInvoker? coachInvoke;
  final NudgeService? nudgeService;
  final EnvironmentService? environmentService;

  const _AuthGate({
    required this.authService,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.storyService,
    required this.modeService,
    required this.dataSource,
    this.profileService,
    this.mealAnalyzer,
    this.coachInvoke,
    this.nudgeService,
    this.environmentService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: authService.authStateChanges,
      initialData: authService.currentUser,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          return WelcomeScreen(authService: authService);
        }
        // Keyed by account id: a different account gets a fresh guard
        // run (and a fresh AppShell), never the previous user's screens.
        return _OwnedShell(
          key: ValueKey(user.id),
          userId: user.id,
          store: store,
          profileService: profileService,
          authService: authService,
          builder: (restart) => AppShell(
            onLocalDataDeleted: restart,
            store: store,
            syncService: syncService,
            readoutService: readoutService,
            storyService: storyService,
            modeService: modeService,
            dataSource: dataSource,
            authService: authService,
            profileService: profileService,
            mealAnalyzer: mealAnalyzer,
            coachInvoke: coachInvoke,
        nudgeService: nudgeService,
        environmentService: environmentService,
          ),
        );
      },
    );
  }
}

/// Runs [ensureLocalDataBelongsTo] once per signed-in account BEFORE any
/// screen reads the store, so another account's data is never shown.
class _OwnedShell extends StatefulWidget {
  final String userId;
  final HealthStore store;
  final ProfileService? profileService;
  final AuthService? authService;

  /// Builds the app; `restart` re-runs these first-run checks (used
  /// after "Delete data on this phone").
  final Widget Function(VoidCallback restart) builder;

  const _OwnedShell({
    super.key,
    required this.userId,
    required this.store,
    required this.builder,
    this.profileService,
    this.authService,
  });

  @override
  State<_OwnedShell> createState() => _OwnedShellState();
}

class _OwnedShellState extends State<_OwnedShell> {
  /// Ownership guard first (may wipe another account's data, including
  /// their onboarding answers), THEN ask: has this user agreed to the
  /// current privacy notice, and have they onboarded?
  late Future<({bool consent, bool onboarding})> _guard = _runGuard();

  Future<({bool consent, bool onboarding})> _runGuard() async {
    await ensureLocalDataBelongsTo(widget.store, widget.userId);
    final needsConsent = await PrivacyService(widget.store).needsConsent();
    final profiles = widget.profileService;
    final needsOnboarding = profiles != null && await profiles.loadProfile() == null;
    return (consent: needsConsent, onboarding: needsOnboarding);
  }

  bool _consentDone = false;
  bool _onboardingDone = false;

  void _restart() {
    if (!mounted) return;
    setState(() {
      _consentDone = false;
      _onboardingDone = false;
      _guard = _runGuard();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({bool consent, bool onboarding})>(
      future: _guard,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // Even if the guard itself failed, never fall through to showing
        // possibly-foreign data silently: show the error instead.
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Couldn't prepare your data on this device. "
                  'Please restart the app.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        final needs = snapshot.data ?? (consent: true, onboarding: false);
        if (needs.consent && !_consentDone) {
          return PrivacyConsentScreen(
            onAgree: () async {
              await PrivacyService(widget.store).recordConsent(adultConfirmed: true);
              if (mounted) setState(() => _consentDone = true);
            },
            onDecline: () async {
              await widget.authService?.signOut();
            },
          );
        }
        final needsOnboarding = needs.onboarding;
        final profiles = widget.profileService;
        if (needsOnboarding && !_onboardingDone && profiles != null) {
          return OnboardingScreen(
            onDone: (profile) async {
              await profiles.saveProfile(profile);
              if (mounted) setState(() => _onboardingDone = true);
            },
          );
        }
        return widget.builder(_restart);
      },
    );
  }
}
