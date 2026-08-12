/// AIZO Packet Framer
/// --------------------
/// Pure Dart, no I/O. Builds and parses the AIZO ring's packet framing:
/// `[length 2B][header 2B][sequence 2B][payload NB][CRC16 2B]`, all
/// fields big-endian. `length` is the byte count of payload+CRC — NOT the
/// total packet length. See aizo_protocol.dart for the header value.
library;

import 'dart:typed_data';

import 'aizo_protocol.dart';

/// A parsed, CRC-validated frame. `null` from [AizoPacketFramer.parse]
/// means "not a valid frame" (too short, or CRC mismatch) — the caller
/// (the response decoder) treats that the same as any other unrecognized
/// input, never a crash.
class AizoParsedFrame {
  final int length;
  final int sequence;
  final Uint8List payload;
  const AizoParsedFrame({required this.length, required this.sequence, required this.payload});
}

class AizoPacketFramer {
  int _sequence = 0;

  /// Builds a full write-ready frame from a command payload, using and
  /// then incrementing this framer's sequence number.
  Uint8List frame(List<int> payload) {
    final crc = AizoPacketFramer.crc16(payload);
    final length = payload.length + 2; // payload + CRC bytes

    final packet = BytesBuilder();
    packet.addByte((length >> 8) & 0xFF);
    packet.addByte(length & 0xFF);
    packet.addByte((aizoFrameHeader >> 8) & 0xFF);
    packet.addByte(aizoFrameHeader & 0xFF);
    packet.addByte((_sequence >> 8) & 0xFF);
    packet.addByte(_sequence & 0xFF);
    packet.add(payload);
    packet.addByte((crc >> 8) & 0xFF);
    packet.addByte(crc & 0xFF);

    _sequence = (_sequence + 1) & 0xFFFF;
    return packet.toBytes();
  }

  void resetSequence() => _sequence = 0;

  /// Parses raw notify bytes into length/sequence/payload, validating the
  /// trailing CRC16 against the payload. Never throws — returns `null` for
  /// anything too short to be a frame or whose CRC doesn't check out.
  static AizoParsedFrame? parse(List<int> bytes) {
    if (bytes.length < 8) return null;
    final length = (bytes[0] << 8) | bytes[1];
    final sequence = (bytes[4] << 8) | bytes[5];

    final payloadEnd = bytes.length - 2;
    if (payloadEnd <= 6) return null;
    final payload = Uint8List.fromList(bytes.sublist(6, payloadEnd));

    final expectedCrc = (bytes[payloadEnd] << 8) | bytes[payloadEnd + 1];
    if (AizoPacketFramer.crc16(payload) != expectedCrc) return null;

    return AizoParsedFrame(length: length, sequence: sequence, payload: payload);
  }

  /// CRC-CCITT variant used by the AIZO protocol (from decompiled source,
  /// confirmed against real hardware). Computed over payload bytes only.
  static int crc16(List<int> data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      crc = ((crc << 8) | (crc >> 8)) & 0xFFFF;
      crc ^= byte;
      crc ^= (crc & 0xFF) >> 4;
      crc ^= (crc << 12) & 0xFFFF;
      crc ^= ((crc & 0xFF) << 5) & 0xFFFF;
    }
    return crc;
  }
}
