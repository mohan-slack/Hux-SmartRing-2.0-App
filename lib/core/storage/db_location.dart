/// Where the HUX database lives — kept OUT of phone backups.
///
/// The DB holds health readings, meals and journal entries that HUX
/// promises stay on this phone. sqflite's default folder on iOS is
/// Documents, which iCloud backs up (Apple guideline 5.1.3(ii) forbids
/// health data in iCloud). On iOS the DB therefore lives in
/// Library/Application Support/hux-db, a folder the app marks
/// "excluded from backup" (see AppDelegate.swift, channel hux/storage).
/// Android keeps sqflite's folder; backups are switched off in the
/// manifest (allowBackup=false + data_extraction_rules.xml).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const _channel = MethodChannel('hux/storage');
const dbFileName = 'hux.db';

Future<String> huxDatabasePath() async {
  final legacy = p.join(await getDatabasesPath(), dbFileName);
  if (!Platform.isIOS) return legacy;

  String? dir;
  try {
    dir = await _channel.invokeMethod<String>('privateDbDir');
  } catch (_) {
    dir = null;
  }
  if (dir == null || dir.isEmpty) return legacy;

  final target = p.join(dir, dbFileName);
  // One-time move for installs that already have a DB in Documents.
  if (!File(target).existsSync() && File(legacy).existsSync()) {
    try {
      // Side files first, the main file last: if anything fails before
      // the main file moves, the app simply keeps using the old path.
      for (final suffix in const ['-journal', '-wal', '-shm']) {
        final side = File('$legacy$suffix');
        if (side.existsSync()) side.renameSync('$target$suffix');
      }
      File(legacy).renameSync(target);
    } catch (_) {
      return File(target).existsSync() ? target : legacy;
    }
  }
  return target;
}
