/// Consent record, "Download my data", and "Delete" — the DPDP / store
/// privacy controls, kept out of the screens so they can be tested.
library;

import 'dart:convert';

import '../auth/auth_service.dart';
import '../storage/health_store.dart';
import 'privacy_notice.dart';

class ConsentRecord {
  final String version;
  final DateTime at;
  final bool adultConfirmed;

  const ConsentRecord({required this.version, required this.at, required this.adultConfirmed});

  Map<String, Object?> toJson() =>
      {'version': version, 'at': at.toUtc().toIso8601String(), 'adult': adultConfirmed};

  static ConsentRecord? fromJson(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      final at = DateTime.tryParse('${j['at']}');
      if (j['version'] is! String || at == null) return null;
      return ConsentRecord(version: j['version'] as String, at: at, adultConfirmed: j['adult'] == true);
    } catch (_) {
      return null;
    }
  }
}

class PrivacyService {
  static const consentKey = 'privacy_consent';

  final HealthStore _store;
  final AuthService? _auth;
  final Future<void> Function()? _stopReminders;
  final DateTime Function() _now;

  /// [stopReminders] cancels scheduled notifications when data is wiped.
  PrivacyService(this._store, {AuthService? auth, Future<void> Function()? stopReminders, DateTime Function()? now})
      : _auth = auth,
        _stopReminders = stopReminders,
        _now = now ?? DateTime.now;

  Future<void> _cancelReminders() async {
    try {
      await _stopReminders?.call();
    } catch (_) {
      // Reminders are best-effort; never block deleting data over them.
    }
  }

  Future<ConsentRecord?> consent() async => ConsentRecord.fromJson(await _store.readSetting(consentKey));

  /// True when the user hasn't agreed to the CURRENT notice yet.
  Future<bool> needsConsent() async {
    final c = await consent();
    return c == null || c.version != PrivacyNotice.noticeVersion || !c.adultConfirmed;
  }

  Future<void> recordConsent({required bool adultConfirmed}) {
    if (!adultConfirmed) throw ArgumentError('HUX v1 is for adults only');
    return _store.writeSetting(
      consentKey,
      jsonEncode(ConsentRecord(version: PrivacyNotice.noticeVersion, at: _now(), adultConfirmed: true).toJson()),
    );
  }

  /// Everything HUX keeps about the user on this phone, as pretty JSON.
  /// (Nothing health-related is on HUX's servers to add.)
  Future<String> exportJson() async {
    final from = DateTime.utc(2000);
    final to = _now().toUtc().add(const Duration(days: 1));
    final snapshots = await _store.snapshotsBetween(from, to);
    final sleep = await _store.sleepSessionsBetween(from, to);
    final settings = await _store.allSettings();
    Object? decode(String v) {
      try {
        return jsonDecode(v);
      } catch (_) {
        return v;
      }
    }

    final data = {
      'app': LegalConfig.appName,
      'company': LegalConfig.company,
      'exportedAt': _now().toUtc().toIso8601String(),
      'account': {'email': _auth?.currentUser?.email},
      'readings': [for (final s in snapshots) s.toMap()],
      'sleep': [
        for (final s in sleep)
          {
            'bedtime': s.bedtime.toUtc().toIso8601String(),
            'wakeTime': s.wakeTime.toUtc().toIso8601String(),
            'totalSleepMinutes': s.totalSleep.inMinutes,
            'avgHeartRateBpm': s.avgHeartRateBpm,
            'avgHrvMs': s.avgHrvMs,
            'minSpo2Percent': s.minSpo2Percent,
            'stages': [
              for (final g in s.segments)
                {'stage': g.stage.name, 'start': g.start.toUtc().toIso8601String(), 'end': g.end.toUtc().toIso8601String()},
            ],
          },
      ],
      'appData': {for (final e in settings.entries) e.key: decode(e.value)},
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Wipes everything on this phone (readings, journal, meals, chat,
  /// answers, consent). The account stays; the next launch starts fresh.
  Future<void> deleteLocalData() async {
    await _cancelReminders();
    await _store.deleteAllData();
  }

  /// Deletes the account on HUX's servers, then everything on this
  /// phone, then signs out. Server first: if it fails, nothing local is
  /// lost and the user can retry.
  Future<void> deleteAccount() async {
    final auth = _auth;
    if (auth == null) throw StateError('No account service');
    await auth.deleteAccount();
    await _cancelReminders();
    await _store.deleteAllData();
    try {
      await auth.signOut();
    } catch (_) {
      // The account no longer exists; a failed sign-out call is harmless.
    }
  }
}
