/// The HUX app widget. Takes its object graph via constructor injection
/// from the composition root (main.dart) — this file never constructs
/// a RingAdapter, HealthStore, or service itself.

import 'package:flutter/material.dart';

import 'core/meaning/readout_service.dart';
import 'core/meaning/weekly_story.dart';
import 'core/storage/health_store.dart';
import 'core/sync/sync_service.dart';
import 'screens/app_shell.dart';

class HuxApp extends StatelessWidget {
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;
  final WeeklyStoryService storyService;

  const HuxApp({
    super.key,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.storyService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HUX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: AppShell(
        store: store,
        syncService: syncService,
        readoutService: readoutService,
        storyService: storyService,
      ),
    );
  }
}
