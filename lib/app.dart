/// The HUX app widget. Takes its object graph via constructor injection
/// from the composition root (main.dart) — this file never constructs
/// a RingAdapter, HealthStore, or service itself.

import 'package:flutter/material.dart';

import 'core/auth/auth_models.dart';
import 'core/auth/auth_service.dart';
import 'core/meaning/readout_service.dart';
import 'core/meaning/weekly_story.dart';
import 'core/modes/mode_service.dart';
import 'core/ring/data_source.dart';
import 'core/storage/health_store.dart';
import 'core/sync/sync_service.dart';
import 'screens/app_shell.dart';
import 'screens/auth/welcome_screen.dart';
import 'theme/hux_theme.dart';

class HuxApp extends StatelessWidget {
  final AuthService authService;
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;
  final WeeklyStoryService storyService;
  final ModeService modeService;
  final RingDataSource dataSource;

  const HuxApp({
    super.key,
    required this.authService,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.storyService,
    required this.modeService,
    this.dataSource = RingDataSource.mock,
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

  const _AuthGate({
    required this.authService,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.storyService,
    required this.modeService,
    required this.dataSource,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: authService.authStateChanges,
      initialData: authService.currentUser,
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return WelcomeScreen(authService: authService);
        }
        return AppShell(
          store: store,
          syncService: syncService,
          readoutService: readoutService,
          storyService: storyService,
          modeService: modeService,
          dataSource: dataSource,
          authService: authService,
        );
      },
    );
  }
}
