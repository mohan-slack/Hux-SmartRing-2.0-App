/// The HUX app widget. Takes its object graph via constructor injection
/// from the composition root (main.dart) — this file never constructs
/// a RingAdapter, HealthStore, or service itself.

import 'package:flutter/material.dart';

import 'core/meaning/readout_service.dart';
import 'core/storage/health_store.dart';
import 'core/sync/sync_service.dart';
import 'screens/today_screen.dart';

class HuxApp extends StatelessWidget {
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;

  const HuxApp({
    super.key,
    required this.store,
    required this.syncService,
    required this.readoutService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HUX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: TodayScreen(
        store: store,
        syncService: syncService,
        readoutService: readoutService,
      ),
    );
  }
}
