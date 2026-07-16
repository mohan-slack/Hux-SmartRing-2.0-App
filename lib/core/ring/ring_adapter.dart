/// HUX Ring Adapter Interface
/// --------------------------
/// THE most important file in the codebase.
///
/// Rule (wiki page 6): the app talks to THIS interface. Never to a vendor
/// SDK, never to a platform channel directly. Every vendor (mock, eIoT,
/// or a future supplier) is one implementation of this interface.
///
/// If a screen works on MockRingAdapter but breaks on the real ring,
/// the adapter implementation is wrong — not the screen.

import 'ring_models.dart';

abstract class RingAdapter {
  /// Connection state as a stream. UI subscribes and renders calmly.
  Stream<RingConnectionState> get connectionState;

  /// Live snapshots while connected (typically every few minutes —
  /// this is a sampling ring, not a streaming one. Battery is 17mAh.)
  Stream<HealthSnapshot> get liveSnapshots;

  /// Battery updates.
  Stream<int> get batteryPercent;

  /// Begin scanning and connect to the first HUX ring found (or the
  /// previously paired one). Resolves when connected or throws
  /// [RingConnectionException] after timeout.
  Future<RingInfo> connect({Duration timeout = const Duration(seconds: 30)});

  Future<void> disconnect();

  /// Pull everything the ring recorded since [since].
  /// This is the catch-up sync after the phone has been away.
  /// MUST be safe to call repeatedly (idempotent) — the sync layer
  /// deduplicates by timestamp.
  Future<SyncResult> syncSince(DateTime since);

  /// One-shot vibration. Real budget is limited (wiki page 3) —
  /// callers go through the NudgeBudget service, never call this raw.
  Future<void> vibrate();

  Future<RingInfo> getRingInfo();

  /// Release all resources. Adapter is unusable afterwards.
  Future<void> dispose();
}

/// Result of a catch-up sync.
class SyncResult {
  final List<HealthSnapshot> snapshots;
  final List<SleepSession> sleepSessions;
  final DateTime syncedUpTo;

  const SyncResult({
    required this.snapshots,
    required this.sleepSessions,
    required this.syncedUpTo,
  });

  bool get isEmpty => snapshots.isEmpty && sleepSessions.isEmpty;
}

class RingConnectionException implements Exception {
  final String message;
  const RingConnectionException(this.message);
  @override
  String toString() => 'RingConnectionException: $message';
}
