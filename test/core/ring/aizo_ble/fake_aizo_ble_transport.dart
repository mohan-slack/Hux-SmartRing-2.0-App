/// Scriptable [AizoBleTransport] fake for [AizoBleRingAdapter] tests — no
/// real BLE plugin or hardware involved. Test-support file, not a test
/// itself; its simple FIFO-replay logic is covered implicitly through the
/// adapter tests that use it.

import 'dart:async';
import 'dart:typed_data';

import 'package:hux_app/core/ring/aizo_ble/aizo_ble_transport.dart';

class FakeAizoBleTransport implements AizoBleTransport {
  /// Set to make [startScanAndConnect] throw, simulating a scan/connect
  /// failure.
  bool failScan = false;

  /// Set to make [discoverServiceAndCharacteristics] throw.
  bool failDiscovery = false;

  String connectedDeviceIdValue = 'FAKE-DEVICE-ID';

  /// Every frame handed to [writeCommand], in order — lets a test assert
  /// exactly what was sent and how many times.
  final List<Uint8List> writtenFrames = [];

  final _notificationsController = StreamController<Uint8List>.broadcast();
  final _connectionStateController = StreamController<AizoTransportConnectionState>.broadcast();

  /// Queued raw notify-bytes, delivered one-per-[writeCommand] call, in
  /// order — mirrors "one command, one ack." A test wanting an unsolicited
  /// or out-of-band notification should call [emitNotification] directly.
  final List<Uint8List> _queuedResponses = [];

  bool _connected = false;

  @override
  String? get connectedDeviceId => _connected ? connectedDeviceIdValue : null;

  @override
  Stream<Uint8List> get notifications => _notificationsController.stream;

  @override
  Stream<AizoTransportConnectionState> get connectionState => _connectionStateController.stream;

  void queueResponse(Uint8List frame) => _queuedResponses.add(frame);

  void emitNotification(Uint8List frame) => _notificationsController.add(frame);

  /// Simulates the ring unexpectedly dropping mid-session (out of range).
  void simulateDrop() {
    _connected = false;
    _connectionStateController.add(AizoTransportConnectionState.disconnected);
  }

  @override
  Future<void> startScanAndConnect({required String deviceName, required Duration timeout}) async {
    if (failScan) {
      throw StateError('FakeAizoBleTransport: simulated scan/connect failure');
    }
    _connected = true;
    _connectionStateController.add(AizoTransportConnectionState.connected);
  }

  @override
  Future<void> discoverServiceAndCharacteristics({
    required String serviceUuid,
    required String writeCharUuid,
    required String notifyCharUuid,
  }) async {
    if (failDiscovery) {
      throw StateError('FakeAizoBleTransport: simulated discovery failure');
    }
  }

  @override
  Future<void> writeCommand(Uint8List frame) async {
    writtenFrames.add(frame);
    if (_queuedResponses.isNotEmpty) {
      final response = _queuedResponses.removeAt(0);
      // Deliver asynchronously, like a real BLE notify would.
      scheduleMicrotask(() => _notificationsController.add(response));
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _connectionStateController.add(AizoTransportConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await _notificationsController.close();
    await _connectionStateController.close();
  }
}
