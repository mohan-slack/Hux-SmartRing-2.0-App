/// Tests for the mock ring adapter.
/// Run with: flutter test
///
/// These tests define the CONTRACT. When the eIoT adapter is written,
/// the same behavioural expectations apply to it (via a shared test
/// suite) — that is how we prove the swap is safe.

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/ring/mock_ring_adapter.dart';
import 'package:hux_app/core/ring/ring_adapter.dart';
import 'package:hux_app/core/ring/ring_models.dart';

MockRingAdapter freshRing({bool chaos = false}) =>
    MockRingAdapter(seed: 7, chaosMode: chaos);

/// connect() may legitimately fail ~8% of the time (mock simulates
/// real pairing failures). Retry a few times for test stability.
Future<RingInfo> connectWithRetry(RingAdapter ring) async {
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      return await ring.connect();
    } on RingConnectionException {
      continue;
    }
  }
  fail('Could not connect after 5 attempts');
}

void main() {
  group('Connection lifecycle', () {
    test('connect resolves with ring info and reaches connected state',
        () async {
      final ring = freshRing();
      final states = <RingConnectionState>[];
      final sub = ring.connectionState.listen(states.add);

      final info = await connectWithRetry(ring);

      expect(info.deviceId, isNotEmpty);
      expect(info.batteryPercent, inInclusiveRange(0, 100));
      expect(states, contains(RingConnectionState.connected));

      await sub.cancel();
      await ring.dispose();
    });

    test('sync before connect throws, does not crash', () async {
      final ring = freshRing();
      expect(
        () => ring.syncSince(DateTime.now()),
        throwsA(isA<RingConnectionException>()),
      );
      await ring.dispose();
    });
  });

  group('Catch-up sync', () {
    test('24h sync returns snapshots and one night of sleep', () async {
      final ring = freshRing();
      await connectWithRetry(ring);

      final result = await ring.syncSince(
        DateTime.now().subtract(const Duration(hours: 24)),
      );

      // ~1 reading per 10 min over 24h, minus ~7% gaps.
      expect(result.snapshots.length, greaterThan(100));
      // Deterministic by window length, not by wall-clock time-of-day —
      // see the anchor-scheme comment in mock_ring_adapter.dart. This
      // used to flake when run in the first ~7h after local midnight.
      expect(result.sleepSessions.length, 1);
      expect(result.syncedUpTo.isAfter(result.snapshots.last.timestamp),
          isTrue);

      await ring.dispose();
    });

    test('missing readings exist: nulls/gaps are part of the contract',
        () async {
      final ring = freshRing();
      await connectWithRetry(ring);

      final result = await ring.syncSince(
        DateTime.now().subtract(const Duration(hours: 48)),
      );

      // Expected samples at 10-min cadence over 48h = 288.
      // The mock drops ~7%, so we must see FEWER than the perfect count.
      expect(result.snapshots.length, lessThan(288));

      await ring.dispose();
    });
  });

  group('Sleep physiology sanity', () {
    test('a night has cycles, deep sleep, REM, and plausible totals',
        () async {
      final ring = freshRing();
      await connectWithRetry(ring);

      final result = await ring.syncSince(
        DateTime.now().subtract(const Duration(hours: 30)),
      );
      final night = result.sleepSessions.first;

      expect(night.totalTimeInBed.inHours, inInclusiveRange(5, 11));
      expect(night.totalSleep, lessThan(night.totalTimeInBed));
      expect(night.stageTotal(SleepStage.deep).inMinutes, greaterThan(30));
      expect(night.stageTotal(SleepStage.rem).inMinutes, greaterThan(30));
      expect(night.segments.first.stage, SleepStage.awake,
          reason: 'sleep onset latency should be modelled');

      await ring.dispose();
    });
  });

  group('Snapshot physiology sanity', () {
    test('values stay in human ranges', () async {
      final ring = freshRing();
      await connectWithRetry(ring);

      final result = await ring.syncSince(
        DateTime.now().subtract(const Duration(hours: 24)),
      );

      for (final s in result.snapshots) {
        if (s.heartRateBpm != null) {
          expect(s.heartRateBpm, inInclusiveRange(38, 190));
        }
        if (s.hrvMs != null) {
          expect(s.hrvMs, inInclusiveRange(12, 140));
        }
        if (s.spo2Percent != null) {
          expect(s.spo2Percent, inInclusiveRange(85, 100));
        }
      }

      await ring.dispose();
    });
  });

  group('Serialization round-trip', () {
    test('HealthSnapshot survives toMap/fromMap unchanged', () {
      final original = HealthSnapshot(
        timestamp: DateTime(2026, 7, 15, 8, 30),
        heartRateBpm: 64,
        hrvMs: 52,
        spo2Percent: 97,
        skinTempCelsius: 33.72,
        steps: 4200,
      );
      final restored = HealthSnapshot.fromMap(original.toMap());

      expect(restored.timestamp, original.timestamp);
      expect(restored.heartRateBpm, original.heartRateBpm);
      expect(restored.hrvMs, original.hrvMs);
      expect(restored.spo2Percent, original.spo2Percent);
      expect(restored.skinTempCelsius, original.skinTempCelsius);
      expect(restored.steps, original.steps);
    });

    test('null readings survive the round-trip too', () {
      final original = HealthSnapshot(timestamp: DateTime(2026, 7, 15));
      final restored = HealthSnapshot.fromMap(original.toMap());
      expect(restored.heartRateBpm, isNull);
      expect(restored.hrvMs, isNull);
    });
  });
}
