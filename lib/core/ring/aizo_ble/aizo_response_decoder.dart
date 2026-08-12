/// AIZO Response Decoder
/// ------------------------
/// Pure Dart, no I/O. Decodes a raw ring notify frame into a typed
/// [AizoResponse]. Never throws — malformed, truncated, CRC-invalid, or
/// unrecognized input always decodes to [AizoUnknownResponse]. This is the
/// one place a temptation to guess at the ring's undecoded activity push
/// (see [AizoResponseCommand.unsolicitedActivityPush]) could creep in —
/// it must not; that command is recognized and explicitly refused, never
/// mapped to a real health value.
library;

import 'dart:typed_data';

import 'aizo_packet_framer.dart';
import 'aizo_protocol.dart';

sealed class AizoResponse {
  const AizoResponse();
}

/// Battery percent, 0-100. Response command [AizoResponseCommand
/// .genericStatus] is shared with other (unimplemented) status queries —
/// disambiguated by the payload's 3rd byte being `0x02`, percent read
/// from the 4th byte.
final class AizoBatteryResponse extends AizoResponse {
  final int percent;
  const AizoBatteryResponse(this.percent);
}

/// Acknowledges [AizoOpcodeTable.sendExperience] — the confirmed one-shot
/// buzz `vibrate()` actually sends.
final class AizoExperienceAck extends AizoResponse {
  const AizoExperienceAck();
}

/// Acknowledges [AizoOpcodeTable.vibratePhone]. Not currently sent by this
/// adapter (see that opcode's doc comment) but decoded for completeness/
/// future use.
final class AizoVibratePhoneAck extends AizoResponse {
  const AizoVibratePhoneAck();
}

/// Anything not decoded into a typed case above. [reason] distinguishes
/// WHY: a genuinely unrecognized command reads differently from "this is
/// the ring's activity push, and we deliberately refuse to guess its
/// layout."
enum AizoUnknownReason { tooShortOrBadCrc, unrecognizedCommand, undecodedActivityPush, unexpectedStatusSubcommand }

final class AizoUnknownResponse extends AizoResponse {
  final Uint8List raw;
  final AizoUnknownReason reason;
  const AizoUnknownResponse(this.raw, this.reason);
}

class AizoResponseDecoder {
  const AizoResponseDecoder._();

  /// Decodes one raw notify-characteristic value. [bytes] is the full
  /// frame (length+header+sequence+payload+CRC), matching what a BLE
  /// notify delivers — framing/CRC validation happens here via
  /// [AizoPacketFramer.parse].
  static AizoResponse decode(List<int> bytes) {
    final frame = AizoPacketFramer.parse(bytes);
    if (frame == null || frame.payload.length < 2) {
      return AizoUnknownResponse(Uint8List.fromList(bytes), AizoUnknownReason.tooShortOrBadCrc);
    }
    final payload = frame.payload;
    final command = (payload[0] << 8) | payload[1];

    switch (command) {
      case AizoResponseCommand.genericStatus:
        if (payload.length < 4 || payload[2] != 0x02) {
          return AizoUnknownResponse(payload, AizoUnknownReason.unexpectedStatusSubcommand);
        }
        return AizoBatteryResponse(payload[3]);

      case AizoResponseCommand.sendExperienceAck:
        return const AizoExperienceAck();

      case AizoResponseCommand.vibratePhoneAck:
        return const AizoVibratePhoneAck();

      case AizoResponseCommand.unsolicitedActivityPush:
        return AizoUnknownResponse(payload, AizoUnknownReason.undecodedActivityPush);

      default:
        return AizoUnknownResponse(payload, AizoUnknownReason.unrecognizedCommand);
    }
  }
}
