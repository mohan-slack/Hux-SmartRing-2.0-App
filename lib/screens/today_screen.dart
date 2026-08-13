/// Today screen — deliberately undesigned plumbing UI. A later design
/// phase restyles this; keep widgets small and composable so that pass
/// is cheap.
///
/// Talks only to [HealthStore] (to check "have we ever synced"),
/// [SyncService], [ReadoutService], and [ModeService] — never to a
/// RingAdapter or SQL.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/meaning/daily_readout.dart';
import '../core/meaning/readout_service.dart';
import '../core/modes/event_mode_engine.dart';
import '../core/modes/mode.dart';
import '../core/modes/mode_service.dart';
import '../core/ring/ring_models.dart';
import '../core/storage/health_store.dart';
import '../core/sync/sync_service.dart';
import '../theme/hux_cards.dart';
import '../theme/hux_glass.dart';
import '../theme/hux_motion.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_vivid_cards.dart';

/// One line combining whichever lifestyle modes are active, or null if
/// none are. Deliberately just concatenation, not a wall of chips —
/// Today's readout is the hero; this rides alongside the event-mode
/// strip as at most one extra line, never a second card.
String? _lifestyleChipText(ActiveContext context) {
  final parts = <String>[];
  if (context.nightShiftActive) parts.add('Night shift');
  if (context.fastDayNumber != null && context.fasting != null) {
    parts.add('${context.fasting!.type.displayName} — '
        'day ${context.fastDayNumber}');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

enum _Phase { syncing, loadingReadout, ready, error }

/// Some adapters (e.g. AizoBleRingAdapter) use a negative sentinel for
/// "battery read failed/unavailable" rather than a plausible-looking
/// percent — never render that sentinel as a literal number here.
int? _sanitizeBattery(int? raw) => (raw == null || raw < 0) ? null : raw;

class TodayScreen extends StatefulWidget {
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;
  final ModeService modeService;

  /// Pinged whenever this tab becomes visible again after the user
  /// switched away and back (see AppShell) — IndexedStack keeps this
  /// screen's State alive rather than rebuilding it, so without this
  /// it would never notice something changed elsewhere (e.g. a mode
  /// started from the Modes tab). Optional: tests that mount
  /// TodayScreen on its own don't need one.
  final Listenable? refreshSignal;

  const TodayScreen({
    super.key,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.modeService,
    this.refreshSignal,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  _Phase _phase = _Phase.loadingReadout;
  DailyReadout? _readout;
  SleepSession? _lastNight;
  ModeStrip? _modeStrip;
  ActiveContext _activeContext = const ActiveContext();
  String? _errorMessage;

  /// Seeded from `syncService.lastRingInfo` right after each sync/load
  /// (an immediate, correct reading), then kept fresh by the live
  /// [SyncService.batteryPercent] subscription below.
  int? _batteryPercent;
  StreamSubscription<int>? _batterySub;

  /// Live instantaneous heart rate for [VividHeartRateCard] — a genuine
  /// point reading, not last night's stored average (that comes from
  /// [_lastNight] instead). Null between readings is normal.
  double? _heartRateBpm;
  StreamSubscription<int?>? _heartRateSub;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onRefreshSignal);
    _batterySub = widget.syncService.batteryPercent.listen((percent) {
      if (mounted) setState(() => _batteryPercent = _sanitizeBattery(percent));
    });
    // A missed live reading (motion, poor contact) is normal — only a
    // REAL non-null tick updates the display; it never regresses an
    // already-known-good reading back to a blank dash.
    _heartRateSub = widget.syncService.heartRateBpm.listen((bpm) {
      if (mounted && bpm != null) setState(() => _heartRateBpm = bpm.toDouble());
    });
    _bootstrap();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onRefreshSignal);
    _batterySub?.cancel();
    _heartRateSub?.cancel();
    super.dispose();
  }

  /// Re-reads the store, but only once we actually have something on
  /// screen to refresh — while still syncing/loading/erroring, the
  /// in-flight bootstrap already has this covered.
  void _onRefreshSignal() {
    if (_phase == _Phase.ready) _loadReadout();
  }

  /// First open: sync automatically only if we've never synced before.
  /// Every later open just loads whatever is already on disk.
  Future<void> _bootstrap() async {
    setState(() {
      _phase = _Phase.loadingReadout;
      _errorMessage = null;
    });

    final everSynced = await widget.store.lastSyncedUpTo() != null;
    if (!mounted) return;

    if (!everSynced) {
      setState(() => _phase = _Phase.syncing);
      final outcome = await widget.syncService.syncNow();
      if (!mounted) return;
      if (!outcome.success) {
        setState(() {
          _phase = _Phase.error;
          _errorMessage = outcome.error;
        });
        return;
      }
    }

    await _loadReadout();
  }

  Future<void> _loadReadout() async {
    if (mounted) setState(() => _phase = _Phase.loadingReadout);
    final readout = await widget.readoutService.today();
    final lastNight = await widget.readoutService.lastNight();
    final modeStrip = await widget.modeService.currentStrip(readout: readout);
    final activeContext = await widget.modeService.activeContext();
    if (!mounted) return;
    setState(() {
      _readout = readout;
      _lastNight = lastNight;
      _modeStrip = modeStrip;
      _activeContext = activeContext;
      // Immediate, correct reading right after a sync — see the field's
      // doc comment. Only overwrites when we actually have one; a
      // subsequent live update from _batterySub can still refine it.
      _batteryPercent = _sanitizeBattery(widget.syncService.lastRingInfo?.batteryPercent) ?? _batteryPercent;
      // Same idea for heart rate: seed from the readout's latest-known
      // reading immediately (see DailyReadout.currentHeartRateBpm), so
      // the card never sits blank waiting for the next live tick.
      _heartRateBpm = readout.currentHeartRateBpm?.toDouble() ?? _heartRateBpm;
      _phase = _Phase.ready;
    });
  }

  /// Pull-to-refresh: sync, then reload. A sync failure here doesn't
  /// blank out an already-visible readout — it just says so quietly.
  Future<void> _refresh() async {
    final outcome = await widget.syncService.syncNow();
    if (!mounted) return;
    if (!outcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't sync with your ring — try again."),
          action: SnackBarAction(label: 'Retry', onPressed: _refresh),
        ),
      );
      return;
    }
    await _loadReadout();
  }

  @override
  Widget build(BuildContext context) => _buildBody();

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.syncing:
        return const _MessageView(message: 'Syncing your ring…');
      case _Phase.loadingReadout:
        return const _MessageView(message: 'Loading your readout…');
      case _Phase.error:
        return _ErrorView(
          message: _errorMessage,
          onRetry: _bootstrap,
        );
      case _Phase.ready:
        return RefreshIndicator(
          onRefresh: _refresh,
          child: _ReadoutBody(
            readout: _readout!,
            lastNight: _lastNight,
            modeStrip: _modeStrip,
            activeContext: _activeContext,
            batteryPercent: _batteryPercent,
            heartRateBpm: _heartRateBpm,
            sendTestBuzz: widget.syncService.sendTestBuzz,
          ),
        );
    }
  }
}

class _MessageView extends StatelessWidget {
  final String message;

  const _MessageView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: HuxSpacing.lg),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A failed BLE sync is normal, not an emergency — no red dialogs.
class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  /// Strips a raw exception's `SomeException: ` prefix — the detail text
  /// underneath the calm headline should read like a sentence, not a
  /// stack trace.
  static String _friendly(String? raw) {
    if (raw == null || raw.isEmpty) {
      return 'It happens — check the ring is nearby and charged.';
    }
    return raw.replaceFirst(RegExp(r'^\w*Exception:\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HuxSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.watch_outlined,
                size: 40, color: HuxColors.mutedText),
            const SizedBox(height: HuxSpacing.md),
            Text("Couldn't sync with your ring",
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: HuxSpacing.xs),
            Text(
              _friendly(message),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: HuxSpacing.lg),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _ReadoutBody extends StatelessWidget {
  final DailyReadout readout;
  final SleepSession? lastNight;
  final ModeStrip? modeStrip;
  final ActiveContext activeContext;
  final int? batteryPercent;
  final double? heartRateBpm;
  final Future<void> Function() sendTestBuzz;

  const _ReadoutBody({
    required this.readout,
    required this.lastNight,
    required this.modeStrip,
    required this.activeContext,
    required this.batteryPercent,
    required this.heartRateBpm,
    required this.sendTestBuzz,
  });

  @override
  Widget build(BuildContext context) {
    final chipText = _lifestyleChipText(activeContext);
    return ListView(
      // Bottom clearance: the body extends behind the glass nav bar
      // (AppShell extendBody), so the last card needs room to scroll
      // fully clear of it.
      padding: const EdgeInsets.fromLTRB(
          HuxSpacing.lg, HuxSpacing.lg, HuxSpacing.lg, HuxGlass.navClearance),
      children: [
        HuxEntrance(
          child: _TodayHeaderCard(
            state: readout.state,
            headline: readout.headline,
            meaning: readout.meaning,
            chipText: chipText,
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 1,
          child: _ActionsList(actions: readout.actions, state: readout.state),
        ),
        const SizedBox(height: HuxSpacing.md),
        HuxEntrance(
          index: 2,
          child: _DataQualityCaption(quality: readout.dataQuality),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 3,
          child: _TodayCardGrid(
            readout: readout,
            lastNight: lastNight,
            heartRateBpm: heartRateBpm,
            batteryPercent: batteryPercent,
            sendTestBuzz: sendTestBuzz,
          ),
        ),
        if (modeStrip != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(index: 4, child: _ModeStripCard(strip: modeStrip!)),
        ],
      ],
    );
  }
}

/// The Today screen's full metric grid — exactly the ten cards the
/// product spec calls for (Stress, Resp. rate, Active cal, Heart Rate,
/// Calories, Sleep Scores, Battery, Test Ring, Min SpO2, Stage
/// breakdown), each individually null-safe: a missing reading renders
/// that ONE card's own documented null convention (em-dash, grey stub,
/// omitted marker — never a fabricated zero), rather than hiding the
/// card or gating the whole grid behind "do we have a night yet."
///
/// This replaces three earlier, overlapping sections — the vitals row,
/// the ring-status row, and Last Night's flat grid + a duplicate
/// sleep-stage-split ring (Sleep Scores' segmented bar already shows
/// that breakdown) — with one consistent set. The three "hero" cards
/// (Heart Rate, Test Ring, Calories) sit in a big-card-plus-two-small
/// block, matching the reference layout; Sleep Scores gets its own
/// full-width row since its segmented bar needs the space; the
/// remaining six are paired two-up except the two that need width for
/// their own bars (Min SpO2, Stage breakdown).
class _TodayCardGrid extends StatelessWidget {
  final DailyReadout readout;
  final SleepSession? lastNight;
  final double? heartRateBpm;
  final int? batteryPercent;
  final Future<void> Function() sendTestBuzz;

  const _TodayCardGrid({
    required this.readout,
    required this.lastNight,
    required this.heartRateBpm,
    required this.batteryPercent,
    required this.sendTestBuzz,
  });

  /// Stress at or below this reads as "Calm", above as "Elevated" — a
  /// plain-language qualifier alongside the number, not a new score.
  static const _stressElevatedThreshold = 50;

  static String _formatInt(double v) => v.round().toString();

  @override
  Widget build(BuildContext context) {
    final night = lastNight;
    final totalSleepMinutes = night?.totalSleep.inMinutes.toDouble() ?? 0;
    final timeInBedMinutes = night?.totalTimeInBed.inMinutes.toDouble() ?? 0;
    // Sleep efficiency — time asleep / time in bed, a standard sleep-
    // tracking metric computed from real segment data, never a
    // fabricated "quality score." Null with no night, or a degenerate
    // (zero-length) time-in-bed.
    final efficiencyPercent =
        (night == null || timeInBedMinutes <= 0) ? null : (totalSleepMinutes / timeInBedMinutes * 100).clamp(0.0, 100.0);
    final segments = night == null || totalSleepMinutes <= 0
        ? const <VividSleepSegment>[]
        : [
            VividSleepSegment(
              label: 'Light',
              percentOfSleep: night.stageTotal(SleepStage.light).inMinutes / totalSleepMinutes,
              color: HuxColors.vividSleepLight,
            ),
            VividSleepSegment(
              label: 'REM',
              percentOfSleep: night.stageTotal(SleepStage.rem).inMinutes / totalSleepMinutes,
              color: HuxColors.vividSleepRem,
            ),
            VividSleepSegment(
              label: 'Deep',
              percentOfSleep: night.stageTotal(SleepStage.deep).inMinutes / totalSleepMinutes,
              color: HuxColors.vividSleepDeep,
            ),
          ];
    final stressQualifier = readout.stressIndex == null
        ? null
        : (readout.stressIndex! > _stressElevatedThreshold ? 'Elevated' : 'Calm');

    return Column(
      children: [
        // Hero block: Heart Rate (big, left) | Test Ring + Calories
        // (stacked, right) — the reference's "big card + pill + small
        // card" grid, used once for the most device/vital-flavored trio.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: VividHeartRateCard(
                  bpm: heartRateBpm,
                  averageBpm: night?.avgHeartRateBpm?.toDouble(),
                ),
              ),
              const SizedBox(width: HuxSpacing.sm),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: HuxTapScale(
                        child: GestureDetector(
                          onTap: () => NudgeModal.show(
                            context,
                            title: 'Test your ring',
                            message: 'Send one vibration to confirm it\'s connected.',
                            icon: Icons.vibration,
                            primaryLabel: 'Buzz now',
                            onPrimary: sendTestBuzz,
                          ),
                          child: HuxHoverLift(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(HuxRadii.vividCard),
                              child: Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Color.alphaBlend(HuxColors.accentIndigo.withValues(alpha: 0.55), HuxColors.card),
                                ),
                                child: Stack(
                                  children: [
                                    Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.vibration, color: HuxColors.ink, size: 28),
                                        const SizedBox(height: HuxSpacing.xs),
                                        Text('Test ring', style: Theme.of(context).textTheme.bodyMedium),
                                      ],
                                    ),
                                    const HuxGlassCorner(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: HuxSpacing.sm),
                    Expanded(
                      child: VividCaloriesCard(kcal: readout.activeEnergyKcal?.toDouble()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HuxSpacing.sm),
        VividSleepScoreCard(efficiencyPercent: efficiencyPercent, segments: segments),
        const SizedBox(height: HuxSpacing.sm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: HeroGaugeCard(
                  label: 'Battery',
                  value: batteryPercent?.toDouble(),
                  unit: '%',
                  size: 96,
                  strokeWidth: 10,
                  cardTint: HuxColors.accentIndigo,
                ),
              ),
              const SizedBox(width: HuxSpacing.sm),
              Expanded(
                child: _DisplayStatTile(
                  label: 'Stress',
                  value: readout.stressIndex?.toDouble(),
                  format: _formatInt,
                  unit: '/100',
                  qualifier: stressQualifier,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: HuxSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _DisplayStatTile(
                label: 'Resp. rate',
                value: night?.avgRespiratoryRateBrpm,
                format: _formatInt,
                unit: 'brpm',
              ),
            ),
            const SizedBox(width: HuxSpacing.sm),
            Expanded(
              child: _DisplayStatTile(
                label: 'Active cal',
                value: readout.activeEnergyKcal?.toDouble(),
                format: _formatInt,
                unit: 'kcal',
              ),
            ),
          ],
        ),
        const SizedBox(height: HuxSpacing.sm),
        SliderRangeCard(
          label: 'Min SpO2',
          value: night?.minSpo2Percent?.toDouble(),
          unit: '%',
          normalRangeMin: 90,
          normalRangeMax: 100,
        ),
        const SizedBox(height: HuxSpacing.sm),
        BarVisualizerCard(
          title: 'Stage breakdown',
          value: night?.totalSleep.inMinutes.toDouble(),
          unit: 'min asleep',
          format: _formatInt,
          bars: [
            BarVisualizerDatum(
              label: 'Awake',
              value: night?.stageTotal(SleepStage.awake).inMinutes.toDouble(),
              color: HuxColors.mutedText,
            ),
            BarVisualizerDatum(
              label: 'Light',
              value: night?.stageTotal(SleepStage.light).inMinutes.toDouble(),
              color: HuxColors.accentCherry,
            ),
            BarVisualizerDatum(
              label: 'Deep',
              value: night?.stageTotal(SleepStage.deep).inMinutes.toDouble(),
              color: HuxColors.accentPurple,
            ),
            BarVisualizerDatum(
              label: 'REM',
              value: night?.stageTotal(SleepStage.rem).inMinutes.toDouble(),
              color: HuxColors.accentPink,
            ),
          ],
        ),
      ],
    );
  }
}

/// Like [_StatTile], but for values that may not exist yet: renders a
/// plain em-dash instead of a counting numeral when [value] is null,
/// so an unavailable metric reads as "no reading", never as "0".
class _DisplayStatTile extends StatelessWidget {
  final String label;
  final double? value;
  final String Function(double) format;
  final String unit;
  final String? qualifier;

  const _DisplayStatTile({
    required this.label,
    required this.value,
    required this.format,
    required this.unit,
    this.qualifier,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final numeralStyle = textTheme.titleLarge?.copyWith(
      fontSize: HuxType.numeral,
      fontWeight: FontWeight.w700,
    );

    // Solid near-black tile — the "Daily Streak" card family (see
    // hux_tokens.dart's file header): plain dark cards for the simpler
    // metrics, reserving the saturated gradients for the hero/vivid
    // cards above.
    return HuxHoverLift(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HuxRadii.vividCard),
        child: Container(
          padding: const EdgeInsets.all(HuxSpacing.md),
          decoration: const BoxDecoration(color: HuxColors.card),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: textTheme.bodySmall),
                  const SizedBox(height: HuxSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (value == null)
                        Text('—', style: numeralStyle)
                      else ...[
                        HuxCountUp(value: value!, format: format, style: numeralStyle),
                        Padding(
                          padding: const EdgeInsets.only(
                              left: HuxSpacing.xs, bottom: HuxSpacing.xs / 2),
                          child: Text(unit, style: textTheme.bodySmall),
                        ),
                      ],
                    ],
                  ),
                  if (qualifier != null) ...[
                    const SizedBox(height: HuxSpacing.xs / 2),
                    Text(qualifier!, style: textTheme.bodySmall),
                  ],
                ],
              ),
              const HuxGlassCorner(),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero block: headline, a soft state-tinted glass panel with a
/// matching outer glow, the "why" sentence, and the lifestyle-mode
/// chip if one's active — all one visually contained unit so the
/// readout reads as the centerpiece of the screen, lit from within by
/// today's recovery state.
class _TodayHeaderCard extends StatelessWidget {
  final RecoveryState state;
  final String headline;
  final String meaning;
  final String? chipText;

  const _TodayHeaderCard({
    required this.state,
    required this.headline,
    required this.meaning,
    required this.chipText,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      frosted: true,
      tint: state.huxColor.withValues(alpha: HuxOpacity.headerWash),
      glow: state.huxColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RecoveryHeader(state: state, headline: headline),
          if (chipText != null) ...[
            const SizedBox(height: HuxSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(chipText!),
                backgroundColor: HuxModeAccent.background
                    .withValues(alpha: HuxOpacity.iconChip),
                labelStyle: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: HuxModeAccent.background),
                side: const BorderSide(color: HuxColors.glassStroke),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
          const SizedBox(height: HuxSpacing.md),
          Text(meaning, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _RecoveryHeader extends StatelessWidget {
  final RecoveryState state;
  final String headline;

  const _RecoveryHeader({required this.state, required this.headline});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: HuxSpacing.sm),
          // Breathes twice on arrival, then settles — the light source
          // of the header's glow (finite, so pumpAndSettle stays happy).
          child: HuxPulseDot(color: state.huxColor),
        ),
        const SizedBox(width: HuxSpacing.sm),
        Expanded(
          child:
              Text(headline, style: Theme.of(context).textTheme.displaySmall),
        ),
      ],
    );
  }
}

class _ActionsList extends StatelessWidget {
  final List<String> actions;
  final RecoveryState state;

  const _ActionsList({required this.actions, required this.state});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: HuxSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Icon(Icons.circle, size: 6, color: state.huxColor),
                ),
                const SizedBox(width: HuxSpacing.sm),
                Expanded(
                  child: Text(action,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DataQualityCaption extends StatelessWidget {
  final DataQuality quality;

  const _DataQualityCaption({required this.quality});

  String get _label => switch (quality) {
        DataQuality.full => 'based on full data from last night',
        DataQuality.partial => 'based on partial data from last night',
        DataQuality.sparse => 'based on sparse data from last night',
      };

  @override
  Widget build(BuildContext context) {
    // bodySmall is already muted-colored (see hux_theme.dart) — no
    // per-widget color override needed.
    return Text(_label, style: Theme.of(context).textTheme.bodySmall);
  }
}

/// The active event mode's compact strip: phase, days-to-go, and
/// today's themed action. On day 0 this is the readiness card instead
/// (same widget — [ModeStrip.phase] already reflects that).
class _ModeStripCard extends StatelessWidget {
  final ModeStrip strip;

  const _ModeStripCard({required this.strip});

  @override
  Widget build(BuildContext context) {
    final isDayZero = strip.phase == ModePhase.theDay;
    final labelStyle = Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(color: HuxModeAccent.background);

    // Day zero is the payoff moment — it gets the full mint glow; the
    // countdown phases stay a quieter mint-tinted glass.
    return GlassPanel(
      frosted: true,
      padding: const EdgeInsets.all(HuxSpacing.md),
      tint:
          HuxModeAccent.background.withValues(alpha: HuxOpacity.activeCardWash),
      glow: isDayZero ? HuxModeAccent.background : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(strip.phaseLabel, style: labelStyle),
              if (!strip.isWrapUp)
                Text(
                  strip.daysToGo == 0 ? 'Today' : '${strip.daysToGo}d to go',
                  style: labelStyle,
                ),
            ],
          ),
          const SizedBox(height: HuxSpacing.xs),
          Text(strip.themedAction,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

