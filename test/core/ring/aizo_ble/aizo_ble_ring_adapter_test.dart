/// Tests for [AizoBleRingAdapter], run entirely over [FakeAizoBleTransport]
/// — no real BLE plugin or hardware. Run with: flutter test

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/ring/aizo_ble/aizo_ble_ring_adapter.dart';
import 'package:hux_app/core/ring/aizo_ble/aizo_packet_framer.dart';
import 'package:hux_app/core/ring/ring_adapter.dart';
import 'package:hux_app/core/ring/ring_models.dart';

import 'fake_aizo_ble_transport.dart';

Uint8List _batteryFrame(int percent) => AizoPacketFramer().frame([0x78, 0x78, 0x02, percent]);
Uint8List _experienceAckFrame() => AizoPacketFramer().frame([0x16, 0x20]);

void main() {
  late FakeAizoBleTransport transport;
  late AizoBleRingAdapter adapter;

  setUp(() {
    transport = FakeAizoBleTransport();
    adapter = AizoBleRingAdapter(transport: transport, ackTimeout: const Duration(milliseconds: 300));
  });

  tearDown(() async {
    await adapter.dispose();
    await transport.dispose();
  });

  group('connect', () {
    test('happy path: scanning -> connecting -> connected, real battery in RingInfo', () async {
      transport.queueResponse(_batteryFrame(64));
      final states = <RingConnectionState>[];
      final sub = adapter.connectionState.listen(states.add);

      final info = await adapter.connect();

      expect(
        states,
        containsAllInOrder([
          RingConnectionState.scanning,
          RingConnectionState.connecting,
          RingConnectionState.connected,
        ]),
      );
      expect(info.batteryPercent, 64);
      expect(info.name, 'AIZO RING');
      expect(info.firmwareVersion, contains('unknown'));

      await sub.cancel();
    });

    test('scan/connect failure surfaces as RingConnectionException, ends disconnected', () async {
      transport.failScan = true;
      final states = <RingConnectionState>[];
      final sub = adapter.connectionState.listen(states.add);

      await expectLater(adapter.connect(), throwsA(isA<RingConnectionException>()));
      // The broadcast connectionState controller delivers events on their
      // own microtask turn, independent of when connect()'s Future
      // itself settles — flush the queue before asserting on `states`.
      await Future<void>.delayed(Duration.zero);

      expect(states.first, RingConnectionState.scanning);
      expect(states.last, RingConnectionState.disconnected);
      await sub.cancel();
    });

    test('a battery-read timeout does not fail connect() — falls back to the honest sentinel', () async {
      // No response queued: the seed getBattery's ack await times out.
      final info = await adapter.connect();
      expect(info.batteryPercent, -1);
    });
  });

  group('vibrate', () {
    test('writes the exact expected sendExperience payload and completes only after the ack', () async {
      transport.queueResponse(_batteryFrame(50)); // connect()'s seed read
      await adapter.connect();
      transport.writtenFrames.clear();

      transport.queueResponse(_experienceAckFrame());
      await adapter.vibrate();

      expect(transport.writtenFrames, hasLength(1));
      final sent = transport.writtenFrames.single;
      final sentPayload = sent.sublist(6, sent.length - 2);
      expect(sentPayload, [0x16, 0x10, 0x04, 0xFF]);
    });

    test('throws if not connected', () {
      expect(adapter.vibrate(), throwsA(isA<RingConnectionException>()));
    });
  });

  group('syncSince', () {
    test('always returns an empty but valid SyncResult, never throws', () async {
      transport.queueResponse(_batteryFrame(50));
      await adapter.connect();

      final result = await adapter.syncSince(DateTime.utc(2020, 1, 1));

      expect(result.isEmpty, isTrue);
      expect(result.snapshots, isEmpty);
      expect(result.sleepSessions, isEmpty);
    });

    test('throws if not connected', () {
      expect(adapter.syncSince(DateTime.now()), throwsA(isA<RingConnectionException>()));
    });
  });

  group('getBattery discipline (firmware buzz-quirk guard)', () {
    test('getBattery is written exactly once per connect()/getRingInfo() call, '
        'never on a timer', () async {
      transport.queueResponse(_batteryFrame(50));
      await adapter.connect();
      final afterConnect = transport.writtenFrames.length;
      expect(afterConnect, 1); // exactly the connect-time seed read

      transport.queueResponse(_batteryFrame(51));
      await adapter.getRingInfo();
      expect(transport.writtenFrames.length, afterConnect + 1);

      // No timer sneaks in another read on its own.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(transport.writtenFrames.length, afterConnect + 1);
    });
  });

  group('robustness', () {
    test('garbage bytes on the notify stream do not crash the adapter or corrupt state', () async {
      transport.queueResponse(_batteryFrame(50));
      await adapter.connect();

      transport.emitNotification(Uint8List.fromList([1, 2, 3]));
      await Future<void>.delayed(Duration.zero);

      transport.queueResponse(_batteryFrame(70));
      final info = await adapter.getRingInfo();
      expect(info.batteryPercent, 70);
    });

    test('an unexpected transport-level drop surfaces as disconnected', () async {
      transport.queueResponse(_batteryFrame(50));
      await adapter.connect();

      final states = <RingConnectionState>[];
      final sub = adapter.connectionState.listen(states.add);
      transport.simulateDrop();
      await Future<void>.delayed(Duration.zero);

      expect(states, contains(RingConnectionState.disconnected));
      await sub.cancel();
    });
  });
}
