/// AIZO Reactive-BLE Transport
/// -----------------------------
/// The ONLY file in this feature allowed to import `flutter_reactive_ble`.
/// Real [AizoBleTransport] implementation — everything else in
/// aizo_ble/ talks to the abstraction, not this plugin.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import 'aizo_ble_transport.dart';

class AizoReactiveBleTransport implements AizoBleTransport {
  final FlutterReactiveBle _ble;

  AizoReactiveBleTransport({FlutterReactiveBle? ble}) : _ble = ble ?? FlutterReactiveBle();

  String? _deviceId;
  QualifiedCharacteristic? _writeChar;

  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connectionSub;
  StreamSubscription<List<int>>? _notifySub;

  final _connectionStateController = StreamController<AizoTransportConnectionState>.broadcast();
  final _notificationsController = StreamController<Uint8List>.broadcast();

  @override
  Stream<Uint8List> get notifications => _notificationsController.stream;

  @override
  Stream<AizoTransportConnectionState> get connectionState => _connectionStateController.stream;

  @override
  String? get connectedDeviceId => _deviceId;

  @override
  Future<void> startScanAndConnect({required String deviceName, required Duration timeout}) async {
    _connectionStateController.add(AizoTransportConnectionState.connecting);

    // Scan with no service filter and match by name client-side — the
    // ring may not advertise FE02 in its scan response (same precedent
    // the reference project's own scanner used).
    final foundDeviceId = Completer<String>();
    final scanSub = _ble.scanForDevices(withServices: const []).listen(
      (device) {
        if (device.name == deviceName && !foundDeviceId.isCompleted) {
          foundDeviceId.complete(device.id);
        }
      },
      onError: (Object e, StackTrace st) {
        if (!foundDeviceId.isCompleted) foundDeviceId.completeError(e, st);
      },
    );
    _scanSub = scanSub;

    final String deviceId;
    try {
      deviceId = await foundDeviceId.future.timeout(timeout);
    } finally {
      await scanSub.cancel();
      _scanSub = null;
    }
    _deviceId = deviceId;

    // connectToDevice's stream IS the connection — it must stay
    // subscribed for the ring to stay connected; cancelling it (in
    // disconnect()) is how we disconnect.
    final connected = Completer<void>();
    _connectionSub = _ble
        .connectToDevice(id: deviceId, connectionTimeout: timeout)
        .listen(
          (update) {
            switch (update.connectionState) {
              case DeviceConnectionState.connecting:
                _connectionStateController.add(AizoTransportConnectionState.connecting);
              case DeviceConnectionState.connected:
                _connectionStateController.add(AizoTransportConnectionState.connected);
                if (!connected.isCompleted) connected.complete();
              case DeviceConnectionState.disconnecting:
                break;
              case DeviceConnectionState.disconnected:
                _connectionStateController.add(AizoTransportConnectionState.disconnected);
                if (!connected.isCompleted) {
                  connected.completeError(StateError('Ring disconnected before connection completed'));
                }
            }
          },
          onError: (Object e, StackTrace st) {
            if (!connected.isCompleted) connected.completeError(e, st);
          },
        );

    await connected.future.timeout(timeout);
  }

  @override
  Future<void> discoverServiceAndCharacteristics({
    required String serviceUuid,
    required String writeCharUuid,
    required String notifyCharUuid,
  }) async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      throw StateError('discoverServiceAndCharacteristics called before a connection was established');
    }

    await _ble.discoverAllServices(deviceId);

    final serviceId = Uuid.parse(serviceUuid);
    _writeChar = QualifiedCharacteristic(
      serviceId: serviceId,
      characteristicId: Uuid.parse(writeCharUuid),
      deviceId: deviceId,
    );
    final notifyChar = QualifiedCharacteristic(
      serviceId: serviceId,
      characteristicId: Uuid.parse(notifyCharUuid),
      deviceId: deviceId,
    );

    _notifySub = _ble.subscribeToCharacteristic(notifyChar).listen(
      (bytes) => _notificationsController.add(Uint8List.fromList(bytes)),
      onError: (Object _, StackTrace __) {
        // Non-fatal here — connectionState is the source of truth for
        // "did we actually lose the ring."
      },
    );
  }

  @override
  Future<void> writeCommand(Uint8List frame) async {
    final writeChar = _writeChar;
    if (writeChar == null) {
      throw StateError('writeCommand called before discoverServiceAndCharacteristics');
    }
    await _ble.writeCharacteristicWithResponse(writeChar, value: frame);
  }

  @override
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    await _scanSub?.cancel();
    _scanSub = null;
    _writeChar = null;
    _deviceId = null;
    _connectionStateController.add(AizoTransportConnectionState.disconnected);
  }
}
