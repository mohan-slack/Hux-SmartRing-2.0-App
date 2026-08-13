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
import 'core/meaning/readout_service.dart';
import 'core/meaning/weekly_story.dart';
import 'core/modes/mode_service.dart';
import 'core/ring/aizo_ble/aizo_ble_ring_adapter.dart';
import 'core/ring/data_source.dart';
import 'core/ring/health_adapter/health_store_ring_adapter.dart';
import 'core/ring/mock_ring_adapter.dart';
import 'core/ring/ring_adapter.dart';
import 'core/storage/sqlite_health_store.dart';
import 'core/sync/sync_service.dart';

/// Which [RingAdapter] to wire up — 'mock' (default), 'health' (dev-only
/// Apple Health / Health Connect adapter), or 'aizo' (real BLE hardware,
/// PROVISIONAL reverse-engineered protocol — see aizo_ble/aizo_protocol
/// .dart; NOT the eventual official eIoT SDK, see AizoBleRingAdapter's
/// header comment for why it isn't named EIoTRingAdapter). Pass
/// `--dart-define=HUX_SOURCE=health` or `=aizo` to a `flutter run`/
/// `flutter build` invocation to switch; the default build is untouched
/// either way.
const _sourceEnv = String.fromEnvironment('HUX_SOURCE', defaultValue: 'mock');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  runApp(HuxApp(
    authService: authService,
    store: store,
    syncService: syncService,
    readoutService: readoutService,
    storyService: storyService,
    modeService: modeService,
    dataSource: dataSource,
  ));
}
