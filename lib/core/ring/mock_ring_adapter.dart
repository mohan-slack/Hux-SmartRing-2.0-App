/// HUX Mock Ring Adapter
/// ---------------------
/// Pretends to be a TM21. Generates physiologically plausible data:
/// circadian heart rate, structured sleep with ~90-minute cycles,
/// occasional missed readings, battery drain, and random disconnects
/// — because the real ring will do all of these.
///
/// Every screen and the whole Meaning/Action engine is built against
/// this first. When the eIoT SDK lands, we write EIoTRingAdapter
/// implementing the same interface, and nothing above it changes.

import 'dart:async';
import 'dart:math';

import 'ring_adapter.dart';
import 'ring_models.dart';

class MockRingAdapter implements RingAdapter {
  final Random _rng;
  final _connState = StreamController<RingConnectionState>.broadcast();
  final _snapshots = StreamController<HealthSnapshot>.broadcast();
  final _battery = StreamController<int>.broadcast();

  Timer? _liveTimer;
  Timer? _chaosTimer;
  int _batteryPercent = 82;
  RingConnectionState _state = RingConnectionState.disconnected;

  /// Personal baseline for the fake wearer. Varying these lets us test
  /// how the Meaning engine reads different bodies.
  final int restingHr;
  final int baselineHrvMs;
  final double baselineTempC;

  /// Set true to make connections flaky — for testing reconnect UX.
  final bool chaosMode;

  MockRingAdapter({
    this.restingHr = 62,
    this.baselineHrvMs = 48,
    this.baselineTempC = 33.6,
    this.chaosMode = false,
    int? seed,
  }) : _rng = Random(seed);

  void _setState(RingConnectionState s) {
    _state = s;
    _connState.add(s);
  }

  @override
  Stream<RingConnectionState> get connectionState => _connState.stream;

  @override
  Stream<HealthSnapshot> get liveSnapshots => _snapshots.stream;

  @override
  Stream<int> get batteryPercent => _battery.stream;

  @override
  Future<RingInfo> connect(
      {Duration timeout = const Duration(seconds: 30)}) async {
    _setState(RingConnectionState.scanning);
    await Future.delayed(Duration(milliseconds: 400 + _rng.nextInt(1200)));
    _setState(RingConnectionState.connecting);
    await Future.delayed(Duration(milliseconds: 300 + _rng.nextInt(900)));

    // The real world: pairing sometimes just fails. ~8% of the time.
    if (_rng.nextDouble() < 0.08) {
      _setState(RingConnectionState.disconnected);
      throw const RingConnectionException(
          'Ring not found. Is it charged and nearby?');
    }

    _setState(RingConnectionState.connected);
    _startLiveFeed();
    if (chaosMode) _startChaos();
    return getRingInfo();
  }

  void _startLiveFeed() {
    // A sampling ring reports every few minutes; sped up here so
    // developers see movement. Interval is not a product promise.
    _liveTimer?.cancel();
    _liveTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_state != RingConnectionState.connected) return;
      _snapshots.add(_snapshotAt(DateTime.now()));
      if (_rng.nextDouble() < 0.15) {
        _batteryPercent = max(1, _batteryPercent - 1);
        _battery.add(_batteryPercent);
      }
    });
  }

  void _startChaos() {
    _chaosTimer?.cancel();
    _chaosTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      if (_state == RingConnectionState.connected &&
          _rng.nextDouble() < 0.35) {
        // BLE dropped: walked out of range, phone slept, cosmic rays.
        _liveTimer?.cancel();
        _setState(RingConnectionState.disconnected);
      }
    });
  }

  @override
  Future<void> disconnect() async {
    _liveTimer?.cancel();
    _chaosTimer?.cancel();
    _setState(RingConnectionState.disconnected);
  }

  @override
  Future<SyncResult> syncSince(DateTime since) async {
    if (_state != RingConnectionState.connected) {
      throw const RingConnectionException('Cannot sync: not connected');
    }
    _setState(RingConnectionState.syncing);
    // Sync time scales with how much data is waiting, like real BLE.
    final hoursGap = DateTime.now().difference(since).inHours.clamp(0, 72);
    await Future.delayed(Duration(milliseconds: 300 + hoursGap * 40));

    final snapshots = <HealthSnapshot>[];
    var t = since;
    final now = DateTime.now();
    while (t.isBefore(now)) {
      // Ring stores a reading every ~10 minutes; ~7% are missing
      // (poor contact, motion). Gaps are part of the contract.
      if (_rng.nextDouble() > 0.07) snapshots.add(_snapshotAt(t));
      t = t.add(const Duration(minutes: 10));
    }

    final sleepSessions = <SleepSession>[];
    // One sleep session per night boundary crossed since `since`.
    var night = DateTime(since.year, since.month, since.day, 23);
    while (night.isBefore(now.subtract(const Duration(hours: 7)))) {
      sleepSessions.add(_generateNight(night));
      night = night.add(const Duration(days: 1));
    }

    _setState(RingConnectionState.connected);
    return SyncResult(
      snapshots: snapshots,
      sleepSessions: sleepSessions,
      syncedUpTo: now,
    );
  }

  /// Heart rate follows a daily rhythm: lowest ~4am, peaks in the
  /// afternoon, small random walk on top.
  HealthSnapshot _snapshotAt(DateTime t) {
    final hourFrac = t.hour + t.minute / 60.0;
    final circadian = sin((hourFrac - 10) / 24 * 2 * pi); // trough ~4am
    final asleep = hourFrac < 6.5 || hourFrac > 23.5;

    final hr = restingHr +
        (asleep ? -6 : 8) +
        (circadian * 7).round() +
        _rng.nextInt(7) -
        3;

    // HRV runs opposite to HR: higher at rest, higher at night.
    final hrv = baselineHrvMs +
        (asleep ? 12 : -4) -
        (circadian * 6).round() +
        _rng.nextInt(9) -
        4;

    final temp = baselineTempC +
        (asleep ? 0.4 : 0.0) +
        circadian * 0.15 +
        (_rng.nextDouble() - 0.5) * 0.2;

    // Steps accumulate through waking hours only.
    final dayProgress = ((hourFrac - 7) / 15).clamp(0.0, 1.0);
    final steps = asleep && hourFrac < 7
        ? 0
        : (8500 * dayProgress * (0.85 + _rng.nextDouble() * 0.3)).round();

    return HealthSnapshot(
      timestamp: t,
      heartRateBpm: hr.clamp(38, 190),
      hrvMs: hrv.clamp(12, 140),
      spo2Percent: asleep ? 94 + _rng.nextInt(5) : 96 + _rng.nextInt(4),
      skinTempCelsius: double.parse(temp.toStringAsFixed(2)),
      steps: steps,
    );
  }

  /// A plausible night: sleep onset, then ~90-minute cycles of
  /// light → deep → light → REM, deep front-loaded, REM back-loaded,
  /// with brief awakenings between some cycles.
  SleepSession _generateNight(DateTime nightAnchor) {
    final bedtime = nightAnchor.add(Duration(minutes: _rng.nextInt(90) - 15));
    final segments = <SleepSegment>[];
    var cursor = bedtime;

    // Sleep onset: awake in bed for 5–25 minutes.
    var next = cursor.add(Duration(minutes: 5 + _rng.nextInt(20)));
    segments.add(
        SleepSegment(start: cursor, end: next, stage: SleepStage.awake));
    cursor = next;

    final cycles = 4 + _rng.nextInt(2); // 4–5 cycles
    for (var c = 0; c < cycles; c++) {
      final early = c < 2;
      final stagePlan = <MapEntry<SleepStage, int>>[
        MapEntry(SleepStage.light, 20 + _rng.nextInt(15)),
        MapEntry(SleepStage.deep,
            early ? 30 + _rng.nextInt(20) : 5 + _rng.nextInt(10)),
        MapEntry(SleepStage.light, 10 + _rng.nextInt(10)),
        MapEntry(SleepStage.rem,
            early ? 8 + _rng.nextInt(8) : 20 + _rng.nextInt(18)),
      ];
      for (final entry in stagePlan) {
        next = cursor.add(Duration(minutes: entry.value));
        segments.add(
            SleepSegment(start: cursor, end: next, stage: entry.key));
        cursor = next;
      }
      // Brief awakening between cycles, sometimes.
      if (_rng.nextDouble() < 0.4) {
        next = cursor.add(Duration(minutes: 1 + _rng.nextInt(4)));
        segments.add(
            SleepSegment(start: cursor, end: next, stage: SleepStage.awake));
        cursor = next;
      }
    }

    return SleepSession(
      bedtime: bedtime,
      wakeTime: cursor,
      segments: segments,
      avgHeartRateBpm: restingHr - 6 + _rng.nextInt(5),
      avgHrvMs: baselineHrvMs + 8 + _rng.nextInt(10),
      minSpo2Percent: 92 + _rng.nextInt(4),
      avgSkinTempCelsius:
          double.parse((baselineTempC + 0.4).toStringAsFixed(2)),
    );
  }

  @override
  Future<void> vibrate() async {
    if (_state != RingConnectionState.connected) {
      throw const RingConnectionException('Cannot vibrate: not connected');
    }
    await Future.delayed(const Duration(milliseconds: 120));
  }

  @override
  Future<RingInfo> getRingInfo() async => RingInfo(
        deviceId: 'MOCK-TM21-0001',
        name: 'HUX Ring',
        firmwareVersion: 'mock-1.0.0',
        batteryPercent: _batteryPercent,
      );

  @override
  Future<void> dispose() async {
    _liveTimer?.cancel();
    _chaosTimer?.cancel();
    await _connState.close();
    await _snapshots.close();
    await _battery.close();
  }
}
