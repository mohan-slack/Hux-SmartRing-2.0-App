/// Composition root — when the eIoT adapter lands, this is the ONLY
/// file where the swap happens. Everything else talks to interfaces
/// (RingAdapter, HealthStore) and never needs to change.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/auth/supabase_auth_service.dart';
import 'core/auth/supabase_config.dart';
import 'core/food/meal_analyzer.dart';
import 'core/environment/environment_service.dart';
import 'core/nudges/notifier.dart';
import 'core/nudges/nudge_service.dart';
import 'core/meaning/readout_service.dart';
import 'core/meaning/weekly_story.dart';
import 'core/modes/mode_service.dart';
import 'core/profile/profile_service.dart';
import 'core/ring/aizo_ble/aizo_ble_ring_adapter.dart';
import 'core/ring/data_source.dart';
import 'core/ring/health_adapter/health_store_ring_adapter.dart';
import 'core/ring/mock_ring_adapter.dart';
import 'core/ring/ring_adapter.dart';
import 'core/storage/sqlite_health_store.dart';
import 'core/sync/sync_service.dart';
import 'core/coach/coach_service.dart';

/// Which [RingAdapter] to wire up — 'mock' (default), 'health' (dev-only
/// Apple Health / Health Connect adapter), or 'aizo' (real BLE hardware,
/// PROVISIONAL reverse-engineered protocol — see aizo_ble/aizo_protocol
/// .dart; NOT the eventual official eIoT SDK, see AizoBleRingAdapter's
/// header comment for why it isn't named EIoTRingAdapter). Pass
/// `--dart-define=HUX_SOURCE=health` or `=aizo` to a `flutter run`/
/// `flutter build` invocation to switch; the default build is untouched
/// either way.
///
/// RELEASE builds default to 'health' (the v1 launch: real data from the
/// user's health app, no HUX ring yet). Debug builds keep the demo.
const _isRelease = bool.fromEnvironment('dart.vm.product');
const _sourceEnv = String.fromEnvironment('HUX_SOURCE', defaultValue: _isRelease ? 'health' : 'mock');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!SupabaseConfig.isConfigured) {
    // Built without `--dart-define-from-file=.env` (or .env is empty).
    runApp(const _SetupErrorApp());
    return;
  }
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.anonKey);
  final authService = SupabaseAuthService();

  final dbPath = p.join(await getDatabasesPath(), 'hux.db');
  final store = await SqliteHealthStore.open(dbPath);

  // The ONE place the source is chosen. Everything below this line
  // only ever talks to the RingAdapter interface — nothing branches on
  // _sourceEnv again. When eIoT delivers their SDK, EIoTRingAdapter
  // joins this switch (or replaces 'mock' as the default) and nowhere
  // else changes.
  final RingDataSource dataSource;
  final RingAdapter ring;
  switch (_sourceEnv) {
    case 'health':
      dataSource = RingDataSource.health;
      ring = HealthStoreRingAdapter();
    case 'aizo':
      dataSource = RingDataSource.aizoBle;
      ring = AizoBleRingAdapter();
    default:
      // chaosMode is off for this demo build so behaviour stays
      // predictable; flip it on locally to exercise the reconnect/
      // retry paths.
      dataSource = RingDataSource.mock;
      ring = MockRingAdapter(seed: 42);
  }

  final syncService = SyncService(ring, store);
  final modeService = ModeService(store);
  final readoutService = ReadoutService(store, modeService: modeService);
  final storyService = WeeklyStoryService(store);
  final profileService = ProfileService(store);
  // Photo meals go through HUX's backend function (the AI key lives
  // there, never in the app). See supabase/functions/analyze-meal.
  Future<Object?> invokeFunction(String name, Map<String, Object?> body) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(name, body: body);
      return response.data;
    } on FunctionException catch (e) {
      // Keep the HTTP status so screens can say WHY (expired sign-in,
      // function not deployed, server error) instead of "couldn't reach".
      debugPrint('Edge function $name failed: ${e.status} ${e.details}');
      throw FunctionCallException(e.status, e.details?.toString());
    }
  }

  final mealAnalyzer = RemoteMealAnalyzer(invokeFunction);
  final notifier = LocalNotifier();
  final nudgeService = NudgeService(store, notifier);
  // Air & heat (Open-Meteo). Free tier is non-commercial only — set
  // apiKey from a paid plan before a paid launch (see the service docs).
  final environmentService = EnvironmentService(
    store,
    notifier: notifier,
    apiKey: SupabaseConfig.openMeteoApiKey.isEmpty ? null : SupabaseConfig.openMeteoApiKey,
  );
  environmentService.refreshAlert().catchError((Object _) {});
  // Rebuild the reminder schedule from saved settings (it can be lost on
  // reinstall/data clear). Never block or crash startup over it.
  nudgeService.resync().catchError((Object _) {});

  runApp(HuxApp(
    authService: authService,
    store: store,
    syncService: syncService,
    readoutService: readoutService,
    storyService: storyService,
    modeService: modeService,
    dataSource: dataSource,
    profileService: profileService,
    mealAnalyzer: mealAnalyzer,
    // Coach chat: supabase/functions/coach-chat (AI key lives there).
    coachInvoke: invokeFunction,
    nudgeService: nudgeService,
    environmentService: environmentService,
  ));
}

/// Shown when the build has no Supabase config, instead of a crash.
class _SetupErrorApp extends StatelessWidget {
  const _SetupErrorApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'HUX isn\'t configured.\n\nCopy .env.example to .env, fill in SUPABASE_URL and '
                'SUPABASE_PUBLISHABLE_KEY, then run:\n\nflutter run --dart-define-from-file=.env',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}
