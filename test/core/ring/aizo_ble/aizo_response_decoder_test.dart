/// Tests for [AizoResponseDecoder]. Run with: flutter test
///
/// Every case here must decode without throwing, per the file's own
/// honesty rule: unrecognized/undecoded bytes always fall to
/// [AizoUnknownResponse], never a guess and never a crash.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/ring/aizo_ble/aizo_packet_framer.dart';
import 'package:hux_app/core/ring/aizo_ble/aizo_response_decoder.dart';

Uint8List _frame(List<int> payload) => AizoPacketFramer().frame(payload);

void main() {
  group('battery response', () {
    test('decodes percent from a genericStatus/0x02 frame', () {
      final response = AizoResponseDecoder.decode(_frame([0x78, 0x78, 0x02, 73]));

      expect(response, isA<AizoBatteryResponse>());
      expect((response as AizoBatteryResponse).percent, 73);
    });

    test('a genericStatus frame with a different sub-command is NOT misparsed as battery', () {
      final response = AizoResponseDecoder.decode(_frame([0x78, 0x78, 0x01, 99]));

      expect(response, isA<AizoUnknownResponse>());
      expect((response as AizoUnknownResponse).reason, AizoUnknownReason.unexpectedStatusSubcommand);
    });
  });

  group('vibration acks', () {
    test('decodes a sendExperience ack', () {
      expect(AizoResponseDecoder.decode(_frame([0x16, 0x20])), isA<AizoExperienceAck>());
    });

    test('decodes a vibratePhone ack', () {
      expect(AizoResponseDecoder.decode(_frame([0x11, 0x08])), isA<AizoVibratePhoneAck>());
    });
  });

  group('unrecognized / undecoded input never throws', () {
    test('empty bytes decode to unknown', () {
      final response = AizoResponseDecoder.decode(const []);

      expect(response, isA<AizoUnknownResponse>());
      expect((response as AizoUnknownResponse).reason, AizoUnknownReason.tooShortOrBadCrc);
    });

    test('a truncated frame decodes to unknown', () {
      final response = AizoResponseDecoder.decode([0x00, 0x05, 0x92, 0x40]);

      expect(response, isA<AizoUnknownResponse>());
      expect((response as AizoUnknownResponse).reason, AizoUnknownReason.tooShortOrBadCrc);
    });

    test('a bad CRC decodes to unknown', () {
      final frame = _frame([0x16, 0x20]);
      final corrupted = [...frame];
      corrupted[corrupted.length - 1] ^= 0xFF;

      final response = AizoResponseDecoder.decode(corrupted);

      expect(response, isA<AizoUnknownResponse>());
      expect((response as AizoUnknownResponse).reason, AizoUnknownReason.tooShortOrBadCrc);
    });

    test('a genuinely unrecognized command decodes to unknown', () {
      final response = AizoResponseDecoder.decode(_frame([0xAB, 0xCD]));

      expect(response, isA<AizoUnknownResponse>());
      expect((response as AizoUnknownResponse).reason, AizoUnknownReason.unrecognizedCommand);
    });

    test('the confirmed-but-undecoded activity push is explicitly tagged, '
        'never guessed at', () {
      // Payload bytes are arbitrary — the layout is genuinely unconfirmed,
      // so this deliberately does NOT assert any structure beyond "we
      // recognized the command and refused to decode it."
      final response = AizoResponseDecoder.decode(_frame([0x79, 0x01, 1, 2, 3, 4]));

      expect(response, isA<AizoUnknownResponse>());
      expect((response as AizoUnknownResponse).reason, AizoUnknownReason.undecodedActivityPush);
    });
  });
}
