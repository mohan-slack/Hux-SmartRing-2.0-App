/// Shared-phone privacy guard (DPDP).
///
/// Health data lives in one local SQLite file. Without this, account B
/// signing in on account A's phone would see A's sleep, HRV and modes.
///
/// Rule: on every sign-in, if the local data belongs to someone else,
/// wipe it first. The SAME account signing back in keeps its data (no
/// needless loss — there is no cloud backup yet).
library;

import '../storage/health_store.dart';

Future<void> ensureLocalDataBelongsTo(HealthStore store, String userId) async {
  final owner = await store.dataOwnerId();
  if (owner != null && owner != userId) {
    await store.deleteAllData();
  }
  if (owner != userId) {
    await store.setDataOwnerId(userId);
  }
}
