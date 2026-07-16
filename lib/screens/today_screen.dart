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
import '../core/modes/event_mode_engine.dart';
import '../core/modes/mode_service.dart';
import '../core/ring/ring_models.dart';
import '../core/storage/health_store.dart';
import '../core/sync/sync_service.dart';

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
    if (!mounted) return;
    setState(() {
      _readout = readout;
      _lastNight = lastNight;
      _modeStrip = modeStrip;
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
          const SizedBox(height: 16),
          Text(message),
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
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.watch_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text("Couldn't sync with your ring"),
            const SizedBox(height: 4),
            Text(
              _friendly(message),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
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

  const _ReadoutBody({
    required this.readout,
    required this.lastNight,
    required this.modeStrip,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _RecoveryHeader(state: readout.state, headline: readout.headline),
        const SizedBox(height: 12),
        Text(readout.meaning),
        const SizedBox(height: 16),
        _ActionsList(actions: readout.actions),
        const SizedBox(height: 12),
        _DataQualityCaption(quality: readout.dataQuality),
        if (modeStrip != null) ...[
          const SizedBox(height: 16),
          _ModeStripCard(strip: modeStrip!),
        ],
        if (lastNight != null) ...[
          const Divider(height: 32),
          _LastNightStats(session: lastNight!),
        ],
      ],
    );
  }
}

class _RecoveryHeader extends StatelessWidget {
  final RecoveryState state;
  final String headline;

  const _RecoveryHeader({required this.state, required this.headline});

  Color get _dotColor => switch (state) {
        RecoveryState.recharged => Colors.green,
        RecoveryState.steady => Colors.teal,
        RecoveryState.stretched => Colors.amber,
        RecoveryState.rundown => Colors.red,
        RecoveryState.learning => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(headline, style: Theme.of(context).textTheme.headlineSmall),
        ),
      ],
    );
  }
}

class _ActionsList extends StatelessWidget {
  final List<String> actions;

  const _ActionsList({required this.actions});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.circle, size: 6),
                const SizedBox(width: 8),
                Expanded(child: Text(action)),
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
    return Text(
      _label,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Colors.grey.shade600),
    );
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
    final scheme = Theme.of(context).colorScheme;
    final isDayZero = strip.phase == ModePhase.theDay;

    return Card(
      color: isDayZero ? scheme.tertiaryContainer : scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(strip.phaseLabel,
                    style: Theme.of(context).textTheme.labelLarge),
                if (!strip.isWrapUp)
                  Text(
                    strip.daysToGo == 0 ? 'Today' : '${strip.daysToGo}d to go',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(strip.themedAction),
          ],
        ),
      ),
    );
  }
}

class _LastNightStats extends StatelessWidget {
  final SleepSession session;

  const _LastNightStats({required this.session});

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  @override
  Widget build(BuildContext context) {
    final rows = <MapEntry<String, String>>[
      MapEntry('Sleep', _formatDuration(session.totalSleep)),
      if (session.avgHrvMs != null)
        MapEntry('Avg HRV', '${session.avgHrvMs} ms'),
      if (session.avgHeartRateBpm != null)
        MapEntry('Avg heart rate', '${session.avgHeartRateBpm} bpm'),
      if (session.minSpo2Percent != null)
        MapEntry('Min SpO2', '${session.minSpo2Percent}%'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Last night', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                // Expanded, not spaceBetween: a long label (a bigger
                // accessibility font, a longer localized string down
                // the line) shrinks/wraps instead of overflowing the
                // row — the value on the right always stays intact.
                Expanded(child: Text(row.key)),
                Text(row.value),
              ],
            ),
          ),
      ],
    );
  }
}
