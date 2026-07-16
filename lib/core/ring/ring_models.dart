/// HUX Ring Data Models
/// ---------------------
/// These models are the single source of truth for what "ring data" means
/// inside the HUX app. Screens, storage, and the Meaning/Action engine all
/// consume THESE types — never vendor SDK types.
///
/// Design rule (from wiki page 3): assume the ring gives us PROCESSED
/// numbers only. No raw PPG, no RR intervals. If we ever win raw data
/// access from eIoT, it gets added as new optional fields — nothing
/// existing breaks.

/// A single point-in-time health reading from the ring.
class HealthSnapshot {
  final DateTime timestamp;

  /// Beats per minute. Null when the ring couldn't get a reading
  /// (motion, poor contact) — null is NORMAL, handle it everywhere.
  final int? heartRateBpm;

  /// Heart rate variability in milliseconds (vendor-computed, likely RMSSD
  /// — algorithm unconfirmed, see wiki item I5).
  final int? hrvMs;

  /// Blood oxygen percentage. Rough sleep-time indicator only.
  final int? spo2Percent;

  /// Skin temperature in Celsius. May be a DEVIATION from baseline
  /// rather than absolute — unconfirmed, see wiki item I4.
  final double? skinTempCelsius;

  /// Cumulative steps since midnight, ring-local.
  final int? steps;

  const HealthSnapshot({
    required this.timestamp,
    this.heartRateBpm,
    this.hrvMs,
    this.spo2Percent,
    this.skinTempCelsius,
    this.steps,
  });

  Map<String, dynamic> toMap() => {
        'timestamp': timestamp.toIso8601String(),
        'heartRateBpm': heartRateBpm,
        'hrvMs': hrvMs,
        'spo2Percent': spo2Percent,
        'skinTempCelsius': skinTempCelsius,
        'steps': steps,
      };

  factory HealthSnapshot.fromMap(Map<String, dynamic> m) => HealthSnapshot(
        timestamp: DateTime.parse(m['timestamp'] as String),
        heartRateBpm: m['heartRateBpm'] as int?,
        hrvMs: m['hrvMs'] as int?,
        spo2Percent: m['spo2Percent'] as int?,
        skinTempCelsius: (m['skinTempCelsius'] as num?)?.toDouble(),
        steps: m['steps'] as int?,
      );
}

/// Sleep stages as the vendor firmware reports them.
/// We do NOT compute these ourselves in v1 (no raw data).
enum SleepStage { awake, light, deep, rem }

/// One continuous block of a single sleep stage.
class SleepSegment {
  final DateTime start;
  final DateTime end;
  final SleepStage stage;

  const SleepSegment({
    required this.start,
    required this.end,
    required this.stage,
  });

  Duration get duration => end.difference(start);
}

/// A full night of sleep, as synced from the ring.
class SleepSession {
  final DateTime bedtime;
  final DateTime wakeTime;
  final List<SleepSegment> segments;

  /// Averages across the night, vendor-computed.
  final int? avgHeartRateBpm;
  final int? avgHrvMs;
  final int? minSpo2Percent;
  final double? avgSkinTempCelsius;

  const SleepSession({
    required this.bedtime,
    required this.wakeTime,
    required this.segments,
    this.avgHeartRateBpm,
    this.avgHrvMs,
    this.minSpo2Percent,
    this.avgSkinTempCelsius,
  });

  Duration get totalTimeInBed => wakeTime.difference(bedtime);

  Duration get totalSleep => segments
      .where((s) => s.stage != SleepStage.awake)
      .fold(Duration.zero, (sum, s) => sum + s.duration);

  Duration stageTotal(SleepStage stage) => segments
      .where((s) => s.stage == stage)
      .fold(Duration.zero, (sum, s) => sum + s.duration);
}

/// Ring connection states. Disconnection is a NORMAL state the UI
/// must render calmly — not an error dialog.
enum RingConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  syncing,
}

/// Static information about the paired ring.
class RingInfo {
  final String deviceId;
  final String name;
  final String firmwareVersion;
  final int batteryPercent;

  const RingInfo({
    required this.deviceId,
    required this.name,
    required this.firmwareVersion,
    required this.batteryPercent,
  });
}
