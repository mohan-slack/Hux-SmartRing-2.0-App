/// AIZO BLE Ring Adapter
/// ------------------------
/// [RingAdapter] implementation speaking the PROVISIONAL, reverse-
/// engineered AIZO protocol (see aizo_protocol.dart) over real BLE
/// hardware. NOT named `EIoTRingAdapter` — that name is reserved in
/// main.dart for a future OFFICIAL eIoT SDK integration; this one is
/// honestly named after the unofficial protocol it actually speaks.
///
/// HONESTY RULE: only what's confirmed working on real hardware is
/// implemented — battery read, one-shot vibrate, connection lifecycle.
/// Every other [HealthSnapshot] field (HR, sleep, SpO2, steps,
/// respiratory rate, stress, calories) has NO confirmed readout command
/// on this protocol. `liveSnapshots` is created and never fed, exactly
/// like [HealthStoreRingAdapter]'s precedent for a source that can't back
/// a field — never guessed, never fabricated. `syncSince` always returns
/// an honest empty result; there is no confirmed way to pull historical
/// data from this ring, only live device operations.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;

import '../ring_adapter.dart';
import '../ring_models.dart';
import 'aizo_ble_transport.dart';
import 'aizo_packet_framer.dart';
import 'aizo_protocol.dart';
import 'aizo_reactive_ble_transport.dart';
import 'aizo_response_decoder.dart';

/// Honest placeholder — this protocol has no confirmed firmware-version
/// read command. Never invent a plausible-looking version string.
const _unknownFirmwareVersion = 'unknown (not exposed by this protocol)';

/// Sentinel for "battery read failed/timed out" — deliberately NOT a
/// plausible percent (like 0, which would read as "critically low") so
/// any future UI wiring is forced to handle "not a real reading"
/// explicitly rather than silently rendering a fake number.
const _batteryUnavailable = -1;

class AizoBleRingAdapter implements RingAdapter {
  final AizoBleTransport _transport;
  final AizoPacketFramer _framer = AizoPacketFramer();
  final Duration ackTimeout;

  AizoBleRingAdapter({AizoBleTransport? transport, this.ackTimeout = const Duration(seconds: 5)})
      : _transport = transport ?? AizoReactiveBleTransport();

  RingConnectionState _state = RingConnectionState.disconnected;
  int? _lastBattery;

  StreamSubscription<AizoResponse>? _responsesSub;
  StreamSubscription<AizoTransportConnectionState>? _transportConnSub;

  final _connectionStateController = StreamController<RingConnectionState>.broadcast();
  final _liveSnapshotsController = StreamController<HealthSnapshot>.broadcast();
  final _batteryPercentController = StreamController<int>.broadcast();

  @override
  Stream<RingConnectionState> get connectionState => _connectionStateController.stream;

  @override
  Stream<HealthSnapshot> get liveSnapshots => _liveSnapshotsController.stream;

  @override
  Stream<int> get batteryPercent => _batteryPercentController.stream;

  Stream<AizoResponse> get _responses => _transport.notifications.map(AizoResponseDecoder.decode);

  void _setState(RingConnectionState state) {
    _state = state;
    _connectionStateController.add(state);
  }

  @override
  Future<RingInfo> connect({Duration timeout = const Duration(seconds: 30)}) async {
    // Diagnostic logging for hardware bring-up — harmless to leave in
    // (only runs when this adapter is actually instantiated, i.e. only
    // under HUX_SOURCE=aizo; never affects the default mock build).
    debugPrint('[AizoBleRingAdapter] scanning for "${AizoBleIds.deviceName}"…');
    _setState(RingConnectionState.scanning);
    try {
      await _transport.startScanAndConnect(deviceName: AizoBleIds.deviceName, timeout: timeout);
      debugPrint('[AizoBleRingAdapter] transport connected, deviceId=${_transport.connectedDeviceId}');
    } catch (e) {
      debugPrint('[AizoBleRingAdapter] scan/connect FAILED: $e');
      _setState(RingConnectionState.disconnected);
      throw RingConnectionException('Could not find ${AizoBleIds.deviceName}: $e');
    }

    _setState(RingConnectionState.connecting);
    try {
      await _transport.discoverServiceAndCharacteristics(
        serviceUuid: AizoBleIds.serviceUuid,
        writeCharUuid: AizoBleIds.writeCharUuid,
        notifyCharUuid: AizoBleIds.notifyCharUuid,
      );
      debugPrint('[AizoBleRingAdapter] service ${AizoBleIds.serviceUuid} + characteristics discovered');
    } catch (e) {
      debugPrint('[AizoBleRingAdapter] service discovery FAILED: $e');
      _setState(RingConnectionState.disconnected);
      throw RingConnectionException('Could not discover ring services: $e');
    }

    _responsesSub?.cancel();
    _responsesSub = _responses.listen((response) {
      if (response case AizoBatteryResponse(:final percent)) {
        _lastBattery = percent;
        _batteryPercentController.add(percent);
      }
      // Everything else (acks, unknowns) is only relevant to whichever
      // in-flight _sendAndAwait call is waiting for it, if any.
    });

    _transportConnSub?.cancel();
    _transportConnSub = _transport.connectionState.listen((transportState) {
      if (transportState == AizoTransportConnectionState.disconnected &&
          _state != RingConnectionState.disconnected) {
        debugPrint('[AizoBleRingAdapter] unexpected drop (ring out of range?)');
        _setState(RingConnectionState.disconnected);
      }
    });

    _setState(RingConnectionState.connected);

    // Seed a real battery reading. Failure here doesn't fail connect() —
    // the ring is genuinely connected either way, just without a fresh
    // percent yet (falls back to the honest "unavailable" sentinel below
    // via getRingInfo's own read-or-fallback below).
    try {
      final percent = await _requestBattery();
      debugPrint('[AizoBleRingAdapter] connected — battery $percent%');
    } catch (e) {
      // See AizoOpcodeTable.getBattery's doc comment — a failed/slow
      // battery read is not a connection failure.
      debugPrint('[AizoBleRingAdapter] connected, but battery read failed/timed out: $e');
    }

    return RingInfo(
      deviceId: _transport.connectedDeviceId ?? AizoBleIds.deviceName,
      name: AizoBleIds.deviceName,
      firmwareVersion: _unknownFirmwareVersion,
      batteryPercent: _lastBattery ?? _batteryUnavailable,
    );
  }

  @override
  Future<void> disconnect() async {
    await _responsesSub?.cancel();
    _responsesSub = null;
    await _transportConnSub?.cancel();
    _transportConnSub = null;
    await _transport.disconnect();
    _setState(RingConnectionState.disconnected);
  }

  @override
  Future<void> vibrate() async {
    if (_state != RingConnectionState.connected) {
      throw const RingConnectionException('Cannot vibrate: not connected');
    }
    debugPrint('[AizoBleRingAdapter] sending vibrate (sendExperience)…');
    // sendExperience, not vibratePhone — a confirmed complete one-shot
    // buzz with no separate stop call, the only honest fit for this
    // parameterless method. See AizoOpcodeTable.vibratePhone's doc comment.
    try {
      await _sendAndAwait<AizoExperienceAck>(
        AizoOpcodeTable.sendExperience.bytes + [aizoVibrateExperienceType, aizoVibrateExperienceIntensity],
      );
      debugPrint('[AizoBleRingAdapter] vibrate acked');
    } catch (e) {
      debugPrint('[AizoBleRingAdapter] vibrate FAILED/timed out: $e');
      rethrow;
    }
  }

  @override
  Future<SyncResult> syncSince(DateTime since) async {
    if (_state != RingConnectionState.connected) {
      throw const RingConnectionException('Cannot sync: not connected');
    }
    _setState(RingConnectionState.syncing);
    // Honest: no confirmed readout command exists for historical health
    // data on this protocol — only live device operations (battery,
    // vibrate) are real. An empty result is truthful, not a stub to fill
    // in later; see this file's header comment.
    final result = SyncResult(snapshots: const [], sleepSessions: const [], syncedUpTo: DateTime.now());
    _setState(RingConnectionState.connected);
    return result;
  }

  @override
  Future<RingInfo> getRingInfo() async {
    if (_state != RingConnectionState.connected) {
      throw const RingConnectionException('Cannot getRingInfo: not connected');
    }
    try {
      await _requestBattery();
    } catch (_) {
      // Fall back to whatever we last knew (possibly still null).
    }
    return RingInfo(
      deviceId: _transport.connectedDeviceId ?? AizoBleIds.deviceName,
      name: AizoBleIds.deviceName,
      firmwareVersion: _unknownFirmwareVersion,
      batteryPercent: _lastBattery ?? _batteryUnavailable,
    );
  }

  @override
  Future<void> dispose() async {
    await _responsesSub?.cancel();
    await _transportConnSub?.cancel();
    await _transport.disconnect();
    await _connectionStateController.close();
    await _liveSnapshotsController.close();
    await _batteryPercentController.close();
  }

  /// Sends [payload] framed, then awaits the first response of type [T]
  /// on the notify stream (subscribed BEFORE the write goes out, so a
  /// fast ack can never arrive before we're listening for it).
  Future<T> _sendAndAwait<T extends AizoResponse>(List<int> payload) async {
    // NOTE: `.firstWhere` returns Future<AizoResponse>, not Future<T> —
    // casting the FUTURE itself (`as Future<T>`) would throw immediately
    // (Future<AizoResponse> is not a Future<T> even when T extends
    // AizoResponse; Dart's generics are reified and non-contravariant
    // here). Casting the awaited VALUE instead is safe, since `is T` in
    // the predicate already guarantees it.
    final responseFuture = _responses.firstWhere((r) => r is T).timeout(ackTimeout).then((r) => r as T);
    await _transport.writeCommand(_framer.frame(payload));
    return responseFuture;
  }

  Future<int> _requestBattery() async {
    final response = await _sendAndAwait<AizoBatteryResponse>(AizoOpcodeTable.getBattery.bytes);
    return response.percent;
  }
}
