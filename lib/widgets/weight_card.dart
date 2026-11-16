/// Weight: latest, change, a trend line and one calm sentence. "Add
/// today" asks for one number. Loads and saves by itself (on the phone).
///
/// [onlyWhenDue] = show nothing unless a weekly weigh-in is due (Home).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/journeys/workout_log.dart';
import '../core/profile/profile_service.dart';
import '../core/profile/user_profile.dart';
import '../core/progress/weight_trend.dart';
import '../core/storage/health_store.dart';
import '../theme/hux_tokens.dart';
import 'hux/hux_kit.dart';

class WeightCard extends StatefulWidget {
  final HealthStore store;
  final Listenable? refreshSignal;
  final bool onlyWhenDue;
  final DateTime Function()? now;

  /// Called after a weight is saved (so other cards can refresh).
  final VoidCallback? onSaved;

  /// Space around the Home tile (kept inside so nothing shows when hidden).
  final EdgeInsetsGeometry padding;

  const WeightCard({super.key, required this.store, this.refreshSignal, this.onlyWhenDue = false, this.now, this.onSaved, this.padding = EdgeInsets.zero});

  @override
  State<WeightCard> createState() => _WeightCardState();
}

class _WeightCardState extends State<WeightCard> {
  List<WeightEntry> _weights = const [];
  WeightTrend? _trend;
  bool _losing = false;
  bool _loaded = false;

  WorkoutLog get _log => WorkoutLog(widget.store, now: widget.now);
  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    var weights = const <WeightEntry>[];
    var losing = false;
    double? height;
    try {
      weights = await _log.weights();
      height = await _log.heightCm();
      losing = (await ProfileService(widget.store).loadProfile())?.goals.contains(Goal.loseWeight) ?? false;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _weights = weights;
      _losing = losing;
      _trend = WeightTrend.of(weights, now: _now, losing: losing, heightCm: height);
      _loaded = true;
    });
  }

  Future<void> _add() async {
    final c = TextEditingController(text: _trend?.latestKg.toStringAsFixed(1) ?? '');
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text("Today's weight"),
            content: TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(suffixText: 'kg', errorText: error),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final kg = double.tryParse(c.text.trim());
                  if (kg == null || kg < 25 || kg > 250) {
                    setLocal(() => error = 'Enter 25–250 kg');
                    return;
                  }
                  Navigator.pop(ctx, kg);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (v == null) return;
    try {
      await _log.addWeight(v);
    } catch (_) {}
    await _load();
    widget.onSaved?.call();
  }

  static String _ago(int days) => days == 0
      ? 'today'
      : days == 1
          ? 'yesterday'
          : '$days days ago';

  @override
  Widget build(BuildContext context) {
    final t = _trend;
    if (widget.onlyWhenDue) {
      // Home: only for people who track weight (or want to lose it).
      final show = _loaded && (t == null ? _losing : t.due);
      if (!show) return const SizedBox.shrink();
      return Padding(
        padding: widget.padding,
        child: HuxTile(
        onTap: _add,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        semanticLabel: 'Weekly weigh-in',
        child: Row(
          children: [
            const Icon(Icons.monitor_weight_outlined, color: HuxColors.ringCharge, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Weekly weigh-in', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: huxInk)),
                  Text(
                    t == null
                        ? 'Add your weight to see your trend.'
                        : 'Last: ${t.latestKg.toStringAsFixed(1)} kg, ${_ago(t.daysSince)}.',
                    style: TextStyle(fontSize: 13, color: huxMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.add_circle_rounded, color: huxInk),
          ],
        ),
        ),
      );
    }

    final recent = _weights.length > 30 ? _weights.sublist(_weights.length - 30) : _weights;
    final change = t?.changeKg;
    return HuxTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HuxTileLabel(
            'Weight',
            trailing: TextButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add today'),
            ),
          ),
          if (t == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Add your weight once a week, same time of day — morning, before food, works best.',
                  style: TextStyle(fontSize: 14, height: 1.35, color: huxMuted)),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                HuxTileValue(t.latestKg.toStringAsFixed(1), unit: 'kg'),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      change != null && change.abs() >= 0.1
                          ? '${change < 0 ? '−' : '+'}${change.abs().toStringAsFixed(1)} kg in ${t.overDays} days'
                          : _ago(t.daysSince),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: huxMuted),
                    ),
                  ),
                ),
              ],
            ),
            if (recent.length >= 2) ...[
              const SizedBox(height: 10),
              HuxSparkline(values: [for (final w in recent) w.kg], color: HuxColors.ringCharge, height: 56),
            ],
            const SizedBox(height: 8),
            Text(t.line, style: TextStyle(fontSize: 14, height: 1.35, color: huxInk)),
          ],
        ],
      ),
    );
  }
}
