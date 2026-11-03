/// Keeps demo and real data apart.
///
/// The app can be built with the simulated ring (`HUX_SOURCE=mock`) or
/// the real health app (`health`). Readings are stored in the same
/// database, so switching used to leave fake nights and steps mixed
/// with real ones — every number on Home was then wrong. This remembers
/// which source filled the database and clears synced readings (never
/// settings, food or check-ins) when it changes.
library;

import '../ring/data_source.dart';
import 'sqlite_health_store.dart';

const _sourceKey = 'data_source';

/// Returns true when old readings were cleared.
Future<bool> guardDataSource(SqliteHealthStore store, RingDataSource current) async {
  final previous = await store.readSetting(_sourceKey);
  var cleared = false;
  if (previous != null && previous != current.name) {
    await store.clearSyncedReadings();
    cleared = true;
  }
  if (previous != current.name) await store.writeSetting(_sourceKey, current.name);
  return cleared;
}
