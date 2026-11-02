/// Workout Report: this week's workouts, kcal per day, weight trend and
/// BMI on the Asian scale. Everything stays on the phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/journeys/workout_log.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';

class WorkoutReportScreen extends StatefulWidget {
  final WorkoutLog log;
  final DateTime Function()? now;

  const WorkoutReportScreen({super.key, required this.log, this.now});

  @override
  State<WorkoutReportScreen> createState() => _WorkoutReportScreenState();
}

typedef _Data = ({List<WorkoutRecord> workouts, List<WeightEntry> weights, double? heightCm});

class _WorkoutReportScreenState extends State<WorkoutReportScreen> {
  late Future<_Data> _future = _load();

  Future<_Data> _load() async =>
      (workouts: await widget.log.all(), weights: await widget.log.weights(), heightCm: await widget.log.heightCm());

  void _reload() {
    final next = _load();
    setState(() {
      _future = next;
    });
  }

  Future<double?> _askNumber({required String title, required String unit, String? initial, required double min, required double max}) {
    final c = TextEditingController(text: initial ?? '');
    return showDialog<double>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(suffixText: unit, errorText: error),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final v = double.tryParse(c.text.trim());
                  if (v == null || v < min || v > max) {
                    setLocal(() => error = 'Enter ${min.round()}–${max.round()} $unit');
                    return;
                  }
                  Navigator.pop(ctx, v);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addWeight(double? last) async {
    final v = await _askNumber(
        title: "Today's weight", unit: 'kg', initial: last?.toStringAsFixed(1), min: 25, max: 250);
    if (v == null) return;
    await widget.log.addWeight(v);
    _reload();
  }

  Future<void> _setHeight(double? cm) async {
    final v = await _askNumber(title: 'Your height', unit: 'cm', initial: cm?.round().toString(), min: 100, max: 230);
    if (v == null) return;
    await widget.log.setHeightCm(v);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: FutureBuilder<_Data>(
        future: _future,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null) return const Center(child: CircularProgressIndicator());
          final now = (widget.now ?? DateTime.now)();
          final today = DateTime(now.year, now.month, now.day);
          final weekStart = today.subtract(const Duration(days: 6));
          final week = d.workouts.where((w) => !w.at.toLocal().isBefore(weekStart)).toList();
          final kcalByDay = [
            for (var i = 6; i >= 0; i--)
              (
                day: today.subtract(Duration(days: i)),
                kcal: d.workouts
                    .where((w) {
                      final l = w.at.toLocal();
                      final t = today.subtract(Duration(days: i));
                      return l.year == t.year && l.month == t.month && l.day == t.day;
                    })
                    .fold<double>(0, (s, w) => s + w.kcal),
              ),
          ];
          final lastKg = d.weights.isEmpty ? null : d.weights.last.kg;
          final bmi = Bmi.of(kg: lastKg, cm: d.heightCm);

          return ListView(
            padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
            children: [
              Row(
                children: [
                  _Big(value: '${week.length}', label: 'workouts\nthis week'),
                  const SizedBox(width: 10),
                  _Big(value: '${(week.fold<int>(0, (s, w) => s + w.seconds) / 60).round()}', label: 'minutes\nthis week'),
                  const SizedBox(width: 10),
                  _Big(value: '≈${week.fold<double>(0, (s, w) => s + w.kcal).round()}', label: 'kcal\nthis week'),
                ],
              ),
              const SizedBox(height: 12),
              HuxTile(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HuxTileLabel('Workout kcal, last 7 days'),
                    const SizedBox(height: 12),
                    _KcalBars(days: kcalByDay),
                    const SizedBox(height: 8),
                    const Text('Estimates from move type, time and your weight.',
                        style: TextStyle(fontSize: 12, color: huxMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _WeightCard(weights: d.weights, onAdd: () => _addWeight(lastKg)),
              const SizedBox(height: 12),
              _BmiCard(bmi: bmi, heightCm: d.heightCm, hasWeight: lastKg != null, onSetHeight: () => _setHeight(d.heightCm)),
              if (d.workouts.isNotEmpty) ...[
                const SizedBox(height: 12),
                HuxTile(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const HuxTileLabel('Recent workouts'),
                      const SizedBox(height: 6),
                      for (final w in d.workouts.reversed.take(6))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(w.title,
                                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxInk)),
                              ),
                              Text(
                                '${_date(w.at.toLocal())} · ${(w.seconds / 60).round()} min · ≈${w.kcal.round()} kcal',
                                style: const TextStyle(fontSize: 13, color: huxMuted),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';
}

class _Big extends StatelessWidget {
  final String value;
  final String label;

  const _Big({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Expanded(
        child: HuxTile(
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: huxInk)),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12, height: 1.25, color: huxMuted)),
            ],
          ),
        ),
      );
}

class _KcalBars extends StatelessWidget {
  final List<({DateTime day, double kcal})> days;

  const _KcalBars({required this.days});

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final top = days.fold<double>(0, (m, d) => d.kcal > m ? d.kcal : m);
    return SizedBox(
      height: 130,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, d) in days.indexed)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(d.kcal > 0 ? '${d.kcal.round()}' : '',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: huxMuted)),
                    const SizedBox(height: 4),
                    Container(
                      height: top <= 0 || d.kcal <= 0 ? 6 : 6 + 84 * d.kcal / top,
                      decoration: BoxDecoration(
                        color: d.kcal <= 0
                            ? huxTrack
                            : i == days.length - 1
                                ? HuxColors.ringSteps
                                : HuxColors.ringSteps.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(_letters[d.day.weekday - 1],
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: huxInk)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WeightCard extends StatelessWidget {
  final List<WeightEntry> weights;
  final VoidCallback onAdd;

  const _WeightCard({required this.weights, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final last = weights.isEmpty ? null : weights.last.kg;
    final first = weights.length < 2 ? null : weights.first.kg;
    final diff = last == null || first == null ? null : last - first;
    final recent = weights.length > 30 ? weights.sublist(weights.length - 30) : weights;
    return HuxTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HuxTileLabel(
            'Weight',
            trailing: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add today'),
            ),
          ),
          if (last == null)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Add your weight once a week, same time of day — morning, before food, works best.',
                  style: TextStyle(fontSize: 14, height: 1.35, color: huxMuted)),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                HuxTileValue(last.toStringAsFixed(1), unit: 'kg'),
                const SizedBox(width: 10),
                if (diff != null && diff.abs() >= 0.1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('${diff < 0 ? '−' : '+'}${diff.abs().toStringAsFixed(1)} kg since ${_short(weights.first.at)}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: huxMuted)),
                  ),
              ],
            ),
            if (recent.length >= 2) ...[
              const SizedBox(height: 10),
              HuxSparkline(values: [for (final w in recent) w.kg], color: HuxColors.ringCharge, height: 56),
            ],
          ],
        ],
      ),
    );
  }

  static String _short(DateTime d) {
    final l = d.toLocal();
    return '${l.day}/${l.month}';
  }
}

class _BmiCard extends StatelessWidget {
  final double? bmi;
  final double? heightCm;
  final bool hasWeight;
  final VoidCallback onSetHeight;

  const _BmiCard({required this.bmi, required this.heightCm, required this.hasWeight, required this.onSetHeight});

  static const _lo = 15.0, _hi = 35.0;
  static const _colors = [HuxColors.ringSleep, HuxColors.ringFood, HuxColors.ringSteps, HuxColors.ringHeart];

  @override
  Widget build(BuildContext context) {
    final b = bmi;
    final band = b == null ? null : Bmi.band(b);
    final range = heightCm == null ? null : Bmi.healthyRange(heightCm!);
    final stops = [_lo, ...Bmi.cutOffs, _hi];
    return HuxTile(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HuxTileLabel(
            'BMI',
            trailing: TextButton(
              onPressed: onSetHeight,
              child: Text(heightCm == null ? 'Add height' : '${heightCm!.round()} cm'),
            ),
          ),
          if (b == null)
            Row(
              children: [
                const Hux3DObject(Hux3D.person, color: HuxColors.ringCharge, size: 44, animate: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    heightCm == null
                        ? 'Add your height${hasWeight ? '' : ' and weight'} to see where you sit on the scale.'
                        : 'Add your weight to see your BMI.',
                    style: const TextStyle(fontSize: 14, height: 1.35, color: huxMuted),
                  ),
                ),
              ],
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                HuxTileValue(b.toStringAsFixed(1)),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(band!.label,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, color: Color.lerp(_colors[band.index], huxInk, 0.25))),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              final x = ((b.clamp(_lo, _hi) - _lo) / (_hi - _lo)) * w;
              double at(double v) => (v - _lo) / (_hi - _lo) * w;
              return SizedBox(
                height: 46,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 12,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Row(
                          children: [
                            for (var i = 0; i < 4; i++)
                              Expanded(
                                flex: ((stops[i + 1] - stops[i]) * 10).round(),
                                child: Container(height: 10, color: _colors[i].withValues(alpha: 0.75)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    for (final cut in Bmi.cutOffs)
                      Positioned(
                        left: at(cut) - 16,
                        width: 32,
                        top: 30,
                        child: Text(cut == cut.roundToDouble() ? '${cut.round()}' : '$cut',
                            textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: huxMuted)),
                      ),
                    Positioned(
                      left: (x - 8).clamp(0, w - 16).toDouble(),
                      top: 7,
                      child: Container(
                        width: 16,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: huxInk, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          if (range != null) ...[
            const SizedBox(height: 10),
            Text('Healthy range for ${heightCm!.round()} cm: ${range.$1.round()}–${range.$2.round()} kg',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: huxInk)),
          ],
          const SizedBox(height: 6),
          const Text(
            'Uses the Asian cut-offs followed in India (healthy 18.5–22.9). BMI is a rough guide — it can\'t tell muscle from fat.',
            style: TextStyle(fontSize: 12, height: 1.35, color: huxMuted),
          ),
        ],
      ),
    );
  }
}
