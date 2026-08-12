/// AIZO Ring BLE Protocol
/// ------------------------
/// PROVISIONAL, reverse-engineered from the AIZO RING Android app
/// (com.eiot.be.ring, Shenzhen eIoT Technology) by decompiling its APK and
/// confirming behavior via live testing against a Rogbid SR10 (firmware
/// 4.15.06). This is NOT an official eIoT SDK — replace with official
/// values if/when eIoT delivers one. `main.dart`'s composition-root switch
/// reserves the name `EIoTRingAdapter` for that future integration; this
/// file backs `AizoBleRingAdapter`, the honestly-named provisional one.
///
/// Every UUID, opcode, and response command the app speaks to this ring
/// lives HERE and only here — no other file may hardcode one.
///
/// `confirmed: true` on an [AizoOpcode] means "observed working on real
/// hardware." `confirmed: false` covers both "inferred from decompiled
/// source, never tested" and "tested and silently ignored by this
/// firmware" — see each constant's doc comment.
library;

/// BLE identifiers (hex strings, as consumed by the transport's UUID type).
class AizoBleIds {
  const AizoBleIds._();

  static const deviceName = 'AIZO RING';
  static const serviceUuid = 'FE02';
  static const writeCharUuid = '0101';
  static const notifyCharUuid = '010A';
}

/// Fixed packet header for app→ring single packets: source=APP(2),
/// dest=TERMINAL(1), ver=2, type=1, ack=0, pkgType=single(0), rfu=0.
const aizoFrameHeader = 0x9240;

/// One AIZO command this app can send. [bytes] is the fixed command
/// prefix — callers append any variable arguments after it.
class AizoOpcode {
  final String name;
  final List<int> bytes;
  final bool confirmed;
  const AizoOpcode({required this.name, required this.bytes, required this.confirmed});
}

class AizoOpcodeTable {
  const AizoOpcodeTable._();

  /// [0x16, 0x10, type, intensity] — short, complete one-shot test buzz.
  /// type=4 (call event) + intensity=0xFF CONFIRMED WORKING as a fire-and-
  /// forget buzz that needs no separate stop command. Response: 0x1620.
  static const sendExperience = AizoOpcode(name: 'sendExperience', bytes: [0x16, 0x10], confirmed: true);

  /// [0x38, 0x38, 0x02] — query battery level. CONFIRMED WORKING.
  ///
  /// ⚠️ Firmware quirk: this command can intermittently trigger a physical
  /// buzz (observed on fw 4.15.06, root cause unconfirmed). Call sparingly
  /// — on connect and on explicit user refresh only, never on a timer. See
  /// the two call sites in AizoBleRingAdapter, which carry this same
  /// warning; do not add a third.
  static const getBattery = AizoOpcode(name: 'getBattery', bytes: [0x38, 0x38, 0x02], confirmed: true);

  /// [0x10, 0x08, type] — call-state-based vibration control (type=1
  /// RINGING starts, type=2 OFFHOOK/3 IDLE stops). CONFIRMED WORKING, but
  /// NOT used by this adapter's `vibrate()` — that method needs a single
  /// complete one-shot buzz with no separate stop call, which
  /// [sendExperience] already provides. Kept here for completeness/future
  /// use (e.g. a future "custom pattern" feature), not currently called.
  static const vibratePhone = AizoOpcode(name: 'vibratePhone', bytes: [0x10, 0x08], confirmed: true);
}

/// Call-state values [AizoOpcodeTable.vibratePhone]'s type byte expects.
class AizoCallState {
  const AizoCallState._();
  static const ringing = 0x01;
  static const offHook = 0x02;
  static const idle = 0x03;
}

/// The vibration event type [AizoOpcodeTable.sendExperience] uses for
/// `vibrate()` — "call event," confirmed as the reliable one-shot buzz.
const aizoVibrateExperienceType = 0x04;
const aizoVibrateExperienceIntensity = 0xFF;

/// The 2-byte command a ring notify frame's payload starts with, echoed
/// back for a given request. [AizoResponseDecoder] switches on these same
/// named values — never a re-hardcoded literal — so a request and its
/// decode always agree.
class AizoResponseCommand {
  const AizoResponseCommand._();

  /// Shared by getBattery and other (unimplemented) status queries,
  /// disambiguated by the payload's 3rd byte — see aizo_response_decoder.dart.
  static const genericStatus = 0x7878;
  static const sendExperienceAck = 0x1620;
  static const vibratePhoneAck = 0x1108;

  /// Unsolicited push the ring sends every ~2-3 minutes, reportedly step/
  /// activity data — but its byte layout was NEVER confirmed in the
  /// reference project. Recognized so it can be labeled "known command,
  /// refused to decode" rather than lumped in with truly unrecognized
  /// bytes — see [AizoUnknownReason.undecodedActivityPush] in
  /// aizo_response_decoder.dart. MUST NOT be guessed at.
  static const unsolicitedActivityPush = 0x7901;
}
