/// HUX Health-Store Ring Adapter (dev tool, not user-facing)
/// -------------------------------------------------------------
/// Reads REAL data from Apple Health (iOS) / Health Connect (Android)
/// via the `health` package and maps it through health_mappers.dart
/// into the exact same [RingAdapter] contract [MockRingAdapter]
/// implements. Purpose: exercise the Meaning engine, Modes, Story, and
/// Trends against real human data before the eIoT ring exists.
///
/// This is NOT a user-facing feature. main.dart only wires it in when
/// launched with `--dart-define=HUX_SOURCE=health`, and the banner
/// pinned above every tab (see app_shell.dart / data_source.dart)
/// always reads "DEV — your health app data (not a HUX ring)" while
/// it's active — screenshots of this build must never be mistaken for
/// either the simulated-ring demo or a real HUX ring.
///
/// READ-ONLY: this adapter never requests write permissions and never
/// calls any of the `health` package's write* methods.
///
/// See health_mappers.dart's file-level doc comment for the SDNN vs
/// RMSSD warning and the stage-less-sleep caveat — both apply here.

import 'dart:async';
import 'dart:io';

import 'package:health/health.dart' as hk;

import '../ring_adapter.dart';
import '../ring_models.dart';
import 'health_mappers.dart';

class HealthStoreRingAdapter implements RingAdapter {
  final hk.Health _health;

  final _connState = StreamController<RingConnectionState>.broadcast();

  /// No live feed concept for this adapter — health apps aren't a
  /// streaming source the way a BLE ring is. Kept open (never fed any
  /// events) so callers can still subscribe exactly like they would
  /// against [MockRingAdapter], per the shared [RingAdapter] contract.
  final _liveSnapshots = StreamController<HealthSnapshot>.broadcast();

  /// Same story as [_liveSnapshots]: no battery concept for a phone's
  /// health app, so this simply never emits.
  final _battery = StreamController<int>.broadcast();

  RingConnectionState _state = RingConnectionState.disconnected;

  HealthStoreRingAdapter({hk.Health? health}) : _health = health ?? hk.Health();

  /// HRV type is platform-specific, not just differently-scaled data on
  /// a shared type (see the file-level HRV NOTE): querying
  /// HEART_RATE_VARIABILITY_RMSSD on Apple Health throws ("Not
  /// available on platform HealthPlatformType.appleHealth") rather than
  /// returning empty, and HealthKit doesn't expose RMSSD at all. Health
  /// Connect's equivalent is RMSSD. So this is the one type picked per
  /// platform rather than requested unconditionally like the rest.
  static hk.HealthDataType get _hrvType => Platform.isIOS
      ? hk.HealthDataType.HEART_RATE_VARIABILITY_SDNN
      : hk.HealthDataType.HEART_RATE_VARIABILITY_RMSSD;

  static List<hk.HealthDataType> get _readTypes => [
        hk.HealthDataType.HEART_RATE,
        _hrvType,
        hk.HealthDataType.BLOOD_OXYGEN,
        hk.HealthDataType.STEPS,
        hk.HealthDataType.BODY_TEMPERATURE,
        hk.HealthDataType.SLEEP_ASLEEP,
        hk.HealthDataType.SLEEP_AWAKE,
        hk.HealthDataType.SLEEP_DEEP,
        hk.HealthDataType.SLEEP_LIGHT,
        hk.HealthDataType.SLEEP_REM,
        // A plain manually-entered sleep span in Apple Health (no
        // sleep-tracking app/Watch involved) writes ONLY this type —
        // see health_mappers.dart's _stageFor doc comment. Without
        // requesting/querying it, the simulator's manual-Health-data
        // verification trick (README) would silently see zero nights.
        hk.HealthDataType.SLEEP_IN_BED,
      ];

  static const _sleepTypes = {
    hk.HealthDataType.SLEEP_ASLEEP,
    hk.HealthDataType.SLEEP_AWAKE,
    hk.HealthDataType.SLEEP_DEEP,
    hk.HealthDataType.SLEEP_LIGHT,
    hk.HealthDataType.SLEEP_REM,
    hk.HealthDataType.SLEEP_IN_BED,
  };

  void _setState(RingConnectionState s) {
    _state = s;
    _connState.add(s);
  }

  @override
  Stream<RingConnectionState> get connectionState => _connState.stream;

  @override
  Stream<HealthSnapshot> get liveSnapshots => _liveSnapshots.stream;

  @override
  Stream<int> get batteryPercent => _battery.stream;

  @override
  Future<RingInfo> connect({Duration timeout = const Duration(seconds: 30)}) async {
    _setState(RingConnectionState.scanning);
    await _health.configure();
    _setState(RingConnectionState.connecting);

    bool granted;
    try {
      granted = await _health.requestAuthorization(_readTypes);
    } catch (_) {
      _setState(RingConnectionState.disconnected);
      throw const RingConnectionException(
          "Couldn't reach your health app. Make sure it's set up on this "
          'device and try again.');
    }

    // NOTE: on iOS, HealthKit will not disclose per-type grant status
    // for privacy reasons — `granted` here only confirms the
    // permission sheet was shown without error, not that every type
    // was actually allowed. A sync can still come back with gaps for
    // types the user quietly denied; that reads the same as any other
    // missing reading (null is normal, per this app's usual contract).
    if (!granted) {
      _setState(RingConnectionState.disconnected);
      throw const RingConnectionException(
          "Health data access wasn't granted. You can turn it on in your "
          'health app\'s settings and try again.');
    }

    _setState(RingConnectionState.connected);
    return getRingInfo();
  }

  @override
  Future<void> disconnect() async {
    _setState(RingConnectionState.disconnected);
  }

  @override
  Future<SyncResult> syncSince(DateTime since) async {
    if (_state != RingConnectionState.connected) {
      throw const RingConnectionException('Cannot sync: not connected');
    }
    _setState(RingConnectionState.syncing);
    final now = DateTime.now();

    // Queried one type at a time, not as one batched call: some
    // (type, platform) combinations throw rather than returning empty
    // — HEART_RATE_VARIABILITY_RMSSD on Apple Health does exactly
    // this ("Not available on platform HealthPlatformType.appleHealth")
    // even though _hrvType already avoids requesting it there. A
    // single unsupported or quietly-denied type must not take down
    // the rest of the sync.
    final points = <hk.HealthDataPoint>[];
    for (final type in _readTypes) {
      try {
        points.addAll(await _health.getHealthDataFromTypes(
          types: [type],
          startTime: since,
          endTime: now,
        ));
      } catch (e) {
        // Dev-tool logging only, not user-facing.
        // ignore: avoid_print
        print('HealthStoreRingAdapter: skipping ${type.name} — $e');
      }
    }

    List<hk.HealthDataPoint> byType(hk.HealthDataType type) =>
        points.where((p) => p.type == type).toList();

    final hrPoints = byType(hk.HealthDataType.HEART_RATE);
    final hrvPoints = byType(_hrvType);
    final spo2Points = byType(hk.HealthDataType.BLOOD_OXYGEN);
    final stepPoints = byType(hk.HealthDataType.STEPS);
    final tempPoints = byType(hk.HealthDataType.BODY_TEMPERATURE);
    final sleepPoints = points.where((p) => _sleepTypes.contains(p.type)).toList();

    final snapshots = mergeSnapshots([
      mapHrSamples(hrPoints),
      mapHrvSamples(hrvPoints),
      mapSpo2(spo2Points),
      mapSteps(stepPoints),
      mapBodyTemp(tempPoints),
    ]);

    final mappedSessions = mapSleepSessions(
      sleepPoints,
      hrPoints: hrPoints,
      hrvPoints: hrvPoints,
      spo2Points: spo2Points,
      tempPoints: tempPoints,
    );

    for (final mapped in mappedSessions) {
      if (!mapped.hadRealStages) {
        // Dev-tool logging only, not user-facing: lets whoever's
        // running this against their own health data notice why a
        // particular night's deep/REM looks thin.
        // ignore: avoid_print
        print('HealthStoreRingAdapter: night starting '
            '${mapped.session.bedtime} came from a stage-less source '
            '(no deep/REM breakdown) — mapped to a single light '
            'segment. Deep/REM will read as under-reported for this '
            'night.');
      }
    }

    _setState(RingConnectionState.connected);
    return SyncResult(
      snapshots: snapshots,
      sleepSessions: [for (final mapped in mappedSessions) mapped.session],
      syncedUpTo: now,
    );
  }

  @override
  Future<void> vibrate() async {
    // No vibration concept for a phone reading its own health app.
  }

  @override
  Future<RingInfo> getRingInfo() async => RingInfo(
        deviceId: 'health-adapter-dev',
        name: 'Health data (dev)',
        firmwareVersion: Platform.isAndroid ? 'healthconnect' : 'healthkit',
        batteryPercent: 100,
      );

  @override
  Future<void> dispose() async {
    await _connState.close();
    await _liveSnapshots.close();
    await _battery.close();
  }
}
