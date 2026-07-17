/// Composition root — when the eIoT adapter lands, this is the ONLY
/// file where the swap happens. Everything else talks to interfaces
/// (RingAdapter, HealthStore) and never needs to change.

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app.dart';
import 'core/meaning/readout_service.dart';
import 'core/meaning/weekly_story.dart';
import 'core/modes/mode_service.dart';
import 'core/ring/mock_ring_adapter.dart';
import 'core/storage/sqlite_health_store.dart';
import 'core/sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbPath = p.join(await getDatabasesPath(), 'hux.db');
  final store = await SqliteHealthStore.open(dbPath);

  // MockRingAdapter until eIoT delivers their SDK — swap it for
  // EIoTRingAdapter here, and nowhere else. chaosMode is off for this
  // demo build so behaviour stays predictable; flip it on locally to
  // exercise the reconnect/retry paths.
  final ring = MockRingAdapter(seed: 42);

  final syncService = SyncService(ring, store);
  final modeService = ModeService(store);
  final readoutService = ReadoutService(store, modeService: modeService);
  final storyService = WeeklyStoryService(store);

  runApp(HuxApp(
    store: store,
    syncService: syncService,
    readoutService: readoutService,
    storyService: storyService,
    modeService: modeService,
  ));
}
