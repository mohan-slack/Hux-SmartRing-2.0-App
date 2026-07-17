/// Today screen — deliberately undesigned plumbing UI. A later design
/// phase restyles this; keep widgets small and composable so that pass
/// is cheap.
///
/// Talks only to [HealthStore] (to check "have we ever synced"),
/// [SyncService], [ReadoutService], and [ModeService] — never to a
/// RingAdapter or SQL.

import 'package:flutter/material.dart';

import '../core/meaning/daily_readout.dart';
import '../core/meaning/readout_service.dart';
import '../core/meaning/sleep_wording.dart';
import '../core/modes/event_mode_engine.dart';
import '../core/modes/mode.dart';
import '../core/modes/mode_service.dart';
import '../core/ring/ring_models.dart';
import '../core/storage/health_store.dart';
import '../core/sync/sync_service.dart';
import '../theme/hux_glass.dart';
import '../theme/hux_motion.dart';
import '../theme/hux_tokens.dart';

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

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onRefreshSignal);
    _bootstrap();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onRefreshSignal);
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

  const _ReadoutBody({
    required this.readout,
    required this.lastNight,
    required this.modeStrip,
    required this.activeContext,
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
        if (modeStrip != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(index: 3, child: _ModeStripCard(strip: modeStrip!)),
        ],
        if (lastNight != null) ...[
          const Divider(height: HuxSpacing.xxl),
          HuxEntrance(
            index: 4,
            child: _LastNightStats(
              session: lastNight!,
              sectionLabel:
                  SleepWording(nightShiftActive: activeContext.nightShiftActive)
                      .sectionLabel,
            ),
          ),
        ],
      ],
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

class _LastNightStats extends StatelessWidget {
  final SleepSession session;
  final String sectionLabel;

  const _LastNightStats({required this.session, required this.sectionLabel});

  static String _formatMinutes(double minutes) {
    final d = Duration(minutes: minutes.round());
    final hours = d.inHours;
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$hours:$mins';
  }

  static String _formatInt(double v) => v.round().toString();

  @override
  Widget build(BuildContext context) {
    final rows = <_StatRow>[
      _StatRow('Sleep', session.totalSleep.inMinutes.toDouble(), _formatMinutes,
          'hrs'),
      if (session.avgHrvMs != null)
        _StatRow('Avg HRV', session.avgHrvMs!.toDouble(), _formatInt, 'ms'),
      if (session.avgHeartRateBpm != null)
        _StatRow('Avg heart rate', session.avgHeartRateBpm!.toDouble(),
            _formatInt, 'bpm'),
      if (session.minSpo2Percent != null)
        _StatRow(
            'Min SpO2', session.minSpo2Percent!.toDouble(), _formatInt, '%'),
    ];
    final textTheme = Theme.of(context).textTheme;

    // A two-column grid of glass stat tiles (widget-board style), not
    // a label:value list — the numbers are what the user came for, so
    // they get the big Space Grotesk treatment. Wrap + LayoutBuilder
    // (intrinsic tile height) instead of a fixed-extent grid, so large
    // accessibility text grows the tiles rather than overflowing them.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(sectionLabel, style: textTheme.labelLarge),
        const SizedBox(height: HuxSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - HuxSpacing.sm) / 2;
            return Wrap(
              spacing: HuxSpacing.sm,
              runSpacing: HuxSpacing.sm,
              children: [
                for (final row in rows)
                  SizedBox(
                    width: tileWidth,
                    child: _StatTile(row: row),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final _StatRow row;

  const _StatTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // titleLarge is a Space Grotesk slot — sized up via the token
    // scale, per the brand's "numbers are Space Grotesk" rule.
    final numeralStyle = textTheme.titleLarge?.copyWith(
      fontSize: HuxType.numeral,
      fontWeight: FontWeight.w700,
    );

    return GlassPanel(
      padding: const EdgeInsets.all(HuxSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(row.label, style: textTheme.bodySmall),
          const SizedBox(height: HuxSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              HuxCountUp(
                value: row.value,
                format: row.format,
                style: numeralStyle,
              ),
              Padding(
                padding: const EdgeInsets.only(
                    left: HuxSpacing.xs, bottom: HuxSpacing.xs / 2),
                child: Text(row.unit, style: textTheme.bodySmall),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One Last-sleep stat: a big counting numeral (Space Grotesk, bold)
/// with a small muted unit label alongside — never one plain string,
/// so the number a user actually cares about reads at a glance. The
/// raw [value] + [format] pair (rather than a pre-formatted string)
/// is what lets the numeral count up on entrance.
class _StatRow {
  final String label;
  final double value;
  final String Function(double) format;
  final String unit;

  const _StatRow(this.label, this.value, this.format, this.unit);
}
