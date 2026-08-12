/// AIZO BLE Transport
/// --------------------
/// The seam between [AizoBleRingAdapter] and whatever BLE plugin actually
/// talks to the radio. Zero plugin imports here — that's the point: this
/// abstraction is what lets the adapter's connect/vibrate/battery logic
/// run over a scriptable fake in tests, with no real hardware or plugin
/// involved. [AizoReactiveBleTransport] is the only real implementation.
library;

import 'dart:typed_data';

enum AizoTransportConnectionState { disconnected, connecting, connected }

abstract class AizoBleTransport {
  /// Scans for a device named [deviceName] and connects to the first one
  /// found, within [timeout]. Throws on timeout or connection failure —
  /// the adapter wraps this as a [RingConnectionException].
  Future<void> startScanAndConnect({required String deviceName, required Duration timeout});

  /// Discovers the named service and its two characteristics, subscribing
  /// to notifications on [notifyCharUuid]. Must be called after a
  /// successful [startScanAndConnect].
  Future<void> discoverServiceAndCharacteristics({
    required String serviceUuid,
    required String writeCharUuid,
    required String notifyCharUuid,
  });

  /// Writes one already-framed packet to the write characteristic.
  Future<void> writeCommand(Uint8List frame);

  /// Raw bytes from the notify characteristic, one event per notification.
  Stream<Uint8List> get notifications;

  /// Native-level connection state — lets the adapter notice an
  /// unexpected mid-session drop (ring walks out of range) rather than
  /// silently going stale.
  Stream<AizoTransportConnectionState> get connectionState;

  /// The platform-level identifier of the currently connected device, if
  /// any — surfaced in [RingInfo.deviceId]. Null before a connection.
  String? get connectedDeviceId;

  Future<void> disconnect();
}
