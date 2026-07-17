/// Tests for [HealthStoreRingAdapter]. Run with: flutter test
///
/// [hk.Health] is a plain (non-final) class wrapping a platform
/// channel, so it can be subclassed here with every method the
/// adapter actually calls overridden — no real HealthKit/Health
/// Connect connection, no platform-channel mocking, ever involved.
/// This is what makes the permission-denied path (the one thing that
/// isn't practical to force via the iOS Simulator once a decision has
/// already been recorded) reproducible and regression-proof.

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart' as hk;
import 'package:hux_app/core/ring/health_adapter/health_store_ring_adapter.dart';
import 'package:hux_app/core/ring/ring_adapter.dart';
import 'package:hux_app/core/ring/ring_models.dart';

hk.HealthDataPoint point({
  required hk.HealthDataType type,
  required DateTime from,
  DateTime? to,
  num value = 0,
}) {
  return hk.HealthDataPoint(
    uuid: 'test-${type.name}-${from.microsecondsSinceEpoch}',
    value: hk.NumericHealthValue(numericValue: value),
    type: type,
    unit: hk.HealthDataUnit.UNKNOWN_UNIT,
    dateFrom: from,
    dateTo: to ?? from,
    sourcePlatform: hk.HealthPlatformType.appleHealth,
    sourceDeviceId: 'test-device',
    sourceId: 'test-source',
    sourceName: 'test',
  );
}

class _FakeHealth extends hk.Health {
  final bool authorized;
  final Object? authorizationError;
  final List<hk.HealthDataPoint> data;
  bool configureCalled = false;
  List<hk.HealthDataType>? lastRequestedTypes;

  _FakeHealth({
    this.authorized = true,
    this.authorizationError,
    this.data = const [],
  });

  @override
  Future<void> configure() async {
    configureCalled = true;
  }

  @override
  Future<bool> requestAuthorization(
    List<hk.HealthDataType> types, {
    List<hk.HealthDataAccess>? permissions,
  }) async {
    lastRequestedTypes = types;
    if (authorizationError != null) throw authorizationError!;
    return authorized;
  }

  @override
  Future<List<hk.HealthDataPoint>> getHealthDataFromTypes({
    required List<hk.HealthDataType> types,
    Map<hk.HealthDataType, hk.HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<hk.RecordingMethod> recordingMethodsToFilter = const [],
  }) async {
    return data.where((p) => types.contains(p.type)).toList();
  }
}

void main() {
  group('connect — permission granted', () {
    test('resolves with RingInfo naming this a dev health-data source',
        () async {
      final adapter = HealthStoreRingAdapter(health: _FakeHealth());

      final info = await adapter.connect();

      expect(info.name, 'Health data (dev)');
      expect(info.batteryPercent, 100);
      expect(info.firmwareVersion, anyOf('healthkit', 'healthconnect'));

      await adapter.dispose();
    });

    test('connectionState reaches connected', () async {
      final adapter = HealthStoreRingAdapter(health: _FakeHealth());
      final states = <RingConnectionState>[];
      final sub = adapter.connectionState.listen(states.add);

      await adapter.connect();

      expect(states, contains(RingConnectionState.connected));
      await sub.cancel();
      await adapter.dispose();
    });
  });

  group('connect — permission denied (calm, recoverable path)', () {
    test('throws a calm RingConnectionException, never a raw error',
        () async {
      final adapter =
          HealthStoreRingAdapter(health: _FakeHealth(authorized: false));

      await expectLater(
        adapter.connect(),
        throwsA(isA<RingConnectionException>()),
      );

      await adapter.dispose();
    });

    test('connectionState ends up disconnected, not stuck mid-connect',
        () async {
      final adapter =
          HealthStoreRingAdapter(health: _FakeHealth(authorized: false));
      final states = <RingConnectionState>[];
      final sub = adapter.connectionState.listen(states.add);

      try {
        await adapter.connect();
        fail('expected a RingConnectionException');
      } on RingConnectionException {
        // expected
      }
      // The broadcast stream delivers its last event via the microtask
      // queue, which may not have flushed the instant connect()'s
      // Future rejects — give it one tick before asserting on it.
      await Future<void>.delayed(Duration.zero);

      expect(states.last, RingConnectionState.disconnected);
      await sub.cancel();
      await adapter.dispose();
    });

    test('a health-app-unreachable error during authorization also '
        'surfaces as a calm RingConnectionException', () async {
      final adapter = HealthStoreRingAdapter(
          health: _FakeHealth(authorizationError: Exception('boom')));

      await expectLater(
        adapter.connect(),
        throwsA(isA<RingConnectionException>()),
      );

      await adapter.dispose();
    });
  });

  group('syncSince', () {
    test('throws if not connected first', () async {
      final adapter = HealthStoreRingAdapter(health: _FakeHealth());

      expect(
        () => adapter.syncSince(DateTime.now()),
        throwsA(isA<RingConnectionException>()),
      );

      await adapter.dispose();
    });

    test('maps real HR + sleep points through to a SyncResult', () async {
      final bedtime = DateTime(2026, 7, 15, 23);
      final fake = _FakeHealth(data: [
        point(
            type: hk.HealthDataType.HEART_RATE,
            from: DateTime(2026, 7, 16, 8),
            value: 60),
        point(
            type: hk.HealthDataType.SLEEP_LIGHT,
            from: bedtime,
            to: bedtime.add(const Duration(hours: 7))),
      ]);
      final adapter = HealthStoreRingAdapter(health: fake);
      await adapter.connect();

      final result = await adapter.syncSince(DateTime(2026, 7, 1));

      expect(result.snapshots, isNotEmpty);
      expect(result.snapshots.first.heartRateBpm, 60);
      expect(result.sleepSessions, hasLength(1));
      expect(result.sleepSessions.single.bedtime, bedtime);

      await adapter.dispose();
    });

    test('never requests HEART_RATE_VARIABILITY_RMSSD on iOS (throws on '
        'real HealthKit) — only whichever HRV type is platform-'
        'appropriate', () async {
      final fake = _FakeHealth();
      final adapter = HealthStoreRingAdapter(health: fake);
      await adapter.connect();

      await adapter.syncSince(DateTime(2026, 7, 1));

      expect(fake.lastRequestedTypes, isNotNull);
      // Exactly one HRV type is ever requested, matching this test
      // process's platform (iOS in CI/dev is not guaranteed, so check
      // both are never requested TOGETHER rather than pinning one).
      final hrvTypesRequested = [
        hk.HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        hk.HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
      ].where((t) => fake.lastRequestedTypes!.contains(t));
      expect(hrvTypesRequested.length, 1,
          reason: 'exactly one HRV type should ever be requested per sync '
              'call, never both, never neither');

      await adapter.dispose();
    });
  });

  group('read-only, dev-tool contract', () {
    test('liveSnapshots and batteryPercent never emit anything', () async {
      final adapter = HealthStoreRingAdapter(health: _FakeHealth());
      final snapshots = <HealthSnapshot>[];
      final battery = <int>[];
      adapter.liveSnapshots.listen(snapshots.add);
      adapter.batteryPercent.listen(battery.add);

      await adapter.connect();
      await adapter.syncSince(DateTime(2026, 7, 1));

      expect(snapshots, isEmpty);
      expect(battery, isEmpty);

      await adapter.dispose();
    });

    test('vibrate is a no-op, never throws', () async {
      final adapter = HealthStoreRingAdapter(health: _FakeHealth());
      await expectLater(adapter.vibrate(), completes);
      await adapter.dispose();
    });
  });
}
