/// Tests for [AizoPacketFramer]. Run with: flutter test
///
/// Golden vectors are the ones confirmed working on real AIZO-protocol
/// hardware in the reference project — see aizo_protocol.dart's header.

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/ring/aizo_ble/aizo_packet_framer.dart';

void main() {
  group('crc16', () {
    test('confirmed vector: [0x10,0x08,0x01] -> 0x1677', () {
      expect(AizoPacketFramer.crc16([0x10, 0x08, 0x01]), 0x1677);
    });
  });

  group('frame', () {
    test('builds the confirmed full frame for [0x10,0x08,0x01]', () {
      final framer = AizoPacketFramer();
      final frame = framer.frame([0x10, 0x08, 0x01]);
      expect(frame, [0x00, 0x05, 0x92, 0x40, 0x00, 0x00, 0x10, 0x08, 0x01, 0x16, 0x77]);
    });

    test('length field is the payload+CRC byte count, not total frame length', () {
      final framer = AizoPacketFramer();
      const payload = [0x38, 0x38, 0x02];
      final frame = framer.frame(payload);
      final length = (frame[0] << 8) | frame[1];

      expect(length, payload.length + 2);
      expect(frame.length, length + 6); // + 2(len) + 2(header) + 2(sn)
    });

    test('sequence number increments per built frame; resetSequence rewinds it', () {
      final framer = AizoPacketFramer();
      final first = framer.frame([0x10, 0x08, 0x01]);
      final second = framer.frame([0x10, 0x08, 0x02]);

      expect((first[4] << 8) | first[5], 0);
      expect((second[4] << 8) | second[5], 1);

      framer.resetSequence();
      final third = framer.frame([0x10, 0x08, 0x01]);
      expect((third[4] << 8) | third[5], 0);
    });
  });

  group('parse', () {
    test('round-trips a framed packet back to its payload and sequence', () {
      final framer = AizoPacketFramer();
      const payload = [0x38, 0x38, 0x02];
      final frame = framer.frame(payload);

      final parsed = AizoPacketFramer.parse(frame);

      expect(parsed, isNotNull);
      expect(parsed!.payload, payload);
      expect(parsed.sequence, 0);
    });

    test('empty input never throws, returns null', () {
      expect(AizoPacketFramer.parse(const []), isNull);
    });

    test('input too short to contain a frame returns null', () {
      expect(AizoPacketFramer.parse([0x00, 0x05, 0x92, 0x40]), isNull);
    });

    test('a mismatched CRC returns null, never throws', () {
      final framer = AizoPacketFramer();
      final frame = framer.frame([0x10, 0x08, 0x01]);
      final corrupted = [...frame];
      corrupted[corrupted.length - 1] ^= 0xFF; // flip the CRC's low byte

      expect(AizoPacketFramer.parse(corrupted), isNull);
    });
  });
}
