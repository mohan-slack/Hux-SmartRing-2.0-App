/// Trends screen — 7-day / 30-day sleep duration, HRV, and resting HR,
/// each night plotted from the user's own history. Deliberately
/// undesigned; a later design phase restyles this.
///
/// Talks only to [HealthStore.sleepSessionsBetween] — no snapshots, no
/// other services. Per-night rows come from the pure helper in
/// core/trends/night_row.dart; this file only charts them.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/meaning/baseline.dart';
import '../core/storage/health_store.dart';
import '../core/trends/night_row.dart';
import '../theme/hux_glass.dart';
import '../theme/hux_motion.dart';
import '../theme/hux_tokens.dart';

/// Single-letter weekday labels, [DateTime.weekday]-indexed (1 = Mon).
const _weekdayInitials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

String _weekdayInitial(DateTime day) => _weekdayInitials[day.weekday - 1];

/// Roughly one label every 7 nights regardless of range, so a 30-day
/// chart doesn't cram 30 overlapping single-letter labels together.
int _weekdayLabelInterval(int rowCount) =>
    rowCount <= 0 ? 1 : (rowCount / 7).ceil().clamp(1, rowCount);

/// "low–high unit", or null when there's nothing to summarize — the
/// small muted hint next to a line chart's title.
String? _minMaxHint(
    List<NightRow> rows, double? Function(NightRow) valueOf, String unit) {
  final values = rows.map(valueOf).whereType<double>().toList();
  if (values.isEmpty) return null;
  final lo = values.reduce((a, b) => a < b ? a : b).round();
  final hi = values.reduce((a, b) => a > b ? a : b).round();
  return '$lo–$hi $unit';
}

/// The most recent night with a reading for this metric — the hero
/// numeral on each chart card. Null when the range has no data.
double? _latestOf(List<NightRow> rows, double? Function(NightRow) valueOf) {
  for (final row in rows.reversed) {
    final value = valueOf(row);
    if (value != null) return value;
  }
  return null;
}

/// "7:10"-style formatting for the sleep card's hero numeral.
String _formatHours(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}

enum _Range { sevenDays, thirtyDays }

extension on _Range {
  int get days => this == _Range.sevenDays ? 7 : 30;
}

class TrendsScreen extends StatefulWidget {
  final HealthStore store;

  const TrendsScreen({super.key, required this.store});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsData {
  final List<NightRow> rows;
  final PersonalBaseline baseline;

  const _TrendsData({required this.rows, required this.baseline});
}

class _TrendsScreenState extends State<TrendsScreen> {
  _Range _range = _Range.sevenDays;
  late Future<_TrendsData> _future;

  /// The baseline always looks back 14 days regardless of the display
  /// range, matching the Meaning engine's own baseline window — the
  /// personal target band should reflect "your usual", not just
  /// whatever's currently on screen.
  static const _baselineWindow = Duration(days: 14);

  @override
  void initState() {
    super.initState();
    _future = _fetch(_range);
  }

  Future<_TrendsData> _fetch(_Range range) async {
    final now = DateTime.now().toUtc();
    final baselineStart = now.subtract(_baselineWindow);
    final displayStart = now.subtract(Duration(days: range.days));
    final queryStart =
        displayStart.isBefore(baselineStart) ? displayStart : baselineStart;

    final sessions = await widget.store.sleepSessionsBetween(queryStart, now);
    // Stress/active-calories are daytime figures with no baseline
    // window of their own (see meaning_engine.dart) — only the display
    // range is fetched, not the wider baseline window sessions use.
    final snapshots = await widget.store.snapshotsBetween(displayStart, now);
    final baseline = PersonalBaseline.fromSleepSessions([
      for (final s in sessions)
        if (!s.bedtime.toUtc().isBefore(baselineStart)) s,
    ]);
    final rows = buildNightRows(
        from: displayStart, to: now, sessions: sessions, snapshots: snapshots);

    return _TrendsData(rows: rows, baseline: baseline);
  }

  void _onRangeChanged(_Range range) {
    setState(() {
      _range = range;
      _future = _fetch(range);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent: this screen lives inside AppShell's IndexedStack,
      // over the ONE shared HuxBackground — it must not paint its own.
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(HuxSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RangeToggle(range: _range, onChanged: _onRangeChanged),
              const SizedBox(height: HuxSpacing.lg),
              Expanded(
                child: FutureBuilder<_TrendsData>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final data = snapshot.data!;
                    final hasAnyNight =
                        data.rows.any((r) => r.sleepDuration != null);
                    if (!hasAnyNight) {
                      return const _EmptyPlaceholder();
                    }
                    return _TrendsCharts(
                        rows: data.rows, baseline: data.baseline);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangeToggle extends StatelessWidget {
  final _Range range;
  final ValueChanged<_Range> onChanged;

  const _RangeToggle({required this.range, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Range>(
      segments: const [
        ButtonSegment(value: _Range.sevenDays, label: Text('7 days')),
        ButtonSegment(value: _Range.thirtyDays, label: Text('30 days')),
      ],
      selected: {range},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HuxSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.show_chart, size: 40, color: HuxColors.mutedText),
            const SizedBox(height: HuxSpacing.md),
            Text('Not enough data to show trends yet',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: HuxSpacing.xs),
            Text(
              'Keep wearing your ring — charts fill in as nights sync.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _TrendsCharts extends StatelessWidget {
  final List<NightRow> rows;
  final PersonalBaseline baseline;

  const _TrendsCharts({required this.rows, required this.baseline});

  @override
  Widget build(BuildContext context) {
    final latestSleep =
        _latestOf(rows, (r) => r.sleepDuration?.inMinutes.toDouble());
    final latestHrv = _latestOf(rows, (r) => r.avgHrvMs);
    final latestHr = _latestOf(rows, (r) => r.avgHeartRateBpm);
    final latestRespRate = _latestOf(rows, (r) => r.avgRespiratoryRateBrpm);
    final latestStress = _latestOf(rows, (r) => r.avgStressIndex);
    final latestActiveKcal = _latestOf(rows, (r) => r.activeEnergyKcal);

    // The sleep delta chip, reference-style: latest night vs the
    // user's own baseline median — never a population number.
    final medianMinutes = baseline.medianTotalSleep?.inMinutes.toDouble();
    int? sleepDeltaPct;
    if (latestSleep != null && medianMinutes != null && medianMinutes > 0) {
      sleepDeltaPct =
          (((latestSleep - medianMinutes) / medianMinutes) * 100).round();
    }

    return ListView(
      // Clearance so the last chart scrolls clear of the glass nav bar.
      padding: const EdgeInsets.only(bottom: HuxGlass.navClearance),
      children: [
        HuxEntrance(
          child: _ChartCard(
            title: 'Sleep duration',
            numeralValue: latestSleep,
            numeralFormat: (v) => _formatHours(Duration(minutes: v.round())),
            unit: 'hrs',
            delta: sleepDeltaPct == null
                ? null
                : _DeltaChip(percent: sleepDeltaPct),
            child: _SleepBarChart(rows: rows, baseline: baseline),
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 1,
          child: _ChartCard(
            title: 'Avg HRV',
            numeralValue: latestHrv,
            numeralFormat: (v) => v.round().toString(),
            unit: 'ms',
            hint: _minMaxHint(rows, (r) => r.avgHrvMs, 'ms'),
            child: _MetricLineChart(rows: rows, valueOf: (r) => r.avgHrvMs),
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 2,
          child: _ChartCard(
            title: 'Avg resting heart rate',
            numeralValue: latestHr,
            numeralFormat: (v) => v.round().toString(),
            unit: 'bpm',
            hint: _minMaxHint(rows, (r) => r.avgHeartRateBpm, 'bpm'),
            child:
                _MetricLineChart(rows: rows, valueOf: (r) => r.avgHeartRateBpm),
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 3,
          child: _ChartCard(
            title: 'Avg respiratory rate',
            numeralValue: latestRespRate,
            numeralFormat: (v) => v.round().toString(),
            unit: 'brpm',
            hint: _minMaxHint(rows, (r) => r.avgRespiratoryRateBrpm, 'brpm'),
            child: _MetricLineChart(
                rows: rows, valueOf: (r) => r.avgRespiratoryRateBrpm),
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 4,
          child: _ChartCard(
            title: 'Stress',
            numeralValue: latestStress,
            numeralFormat: (v) => v.round().toString(),
            unit: '/100',
            hint: _minMaxHint(rows, (r) => r.avgStressIndex, '/100'),
            child: _MetricLineChart(rows: rows, valueOf: (r) => r.avgStressIndex),
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 5,
          child: _ChartCard(
            title: 'Active calories',
            numeralValue: latestActiveKcal,
            numeralFormat: (v) => v.round().toString(),
            unit: 'kcal',
            hint: _minMaxHint(rows, (r) => r.activeEnergyKcal, 'kcal'),
            child:
                _MetricLineChart(rows: rows, valueOf: (r) => r.activeEnergyKcal),
          ),
        ),
      ],
    );
  }
}

/// The little "↑ 6% vs usual" pill beside the sleep hero numeral —
/// mint when at/above the user's own median, amber below. Wellness
/// register: it compares to "your usual", it never judges.
class _DeltaChip extends StatelessWidget {
  final int percent;

  const _DeltaChip({required this.percent});

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final color = up ? HuxColors.accentPink : HuxColors.stretched;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: HuxSpacing.sm, vertical: HuxSpacing.xs / 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: HuxOpacity.iconChip),
        borderRadius: BorderRadius.circular(HuxRadii.chip),
      ),
      child: Text(
        '${up ? '↑' : '↓'} ${percent.abs()}% vs usual',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

/// One glass chart panel, reference-card style: muted title (with an
/// optional min–max hint), a big Space Grotesk hero numeral that
/// counts up to the most recent reading (plus an optional delta chip
/// beside it), then the chart itself. Chart cards are this screen's
/// hero panels, so they carry the real frosted backdrop blur.
class _ChartCard extends StatelessWidget {
  final String title;
  final double? numeralValue;
  final String Function(double) numeralFormat;
  final String unit;
  final String? hint;
  final Widget? delta;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.numeralValue,
    required this.numeralFormat,
    required this.unit,
    this.hint,
    this.delta,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final numeralStyle = textTheme.titleLarge?.copyWith(
      fontSize: HuxType.numeralLarge,
      fontWeight: FontWeight.w700,
    );

    return GlassPanel(
      frosted: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title, style: textTheme.bodySmall),
              if (hint != null) ...[
                const Spacer(),
                Text(hint!, style: textTheme.bodySmall),
              ],
            ],
          ),
          if (numeralValue != null) ...[
            const SizedBox(height: HuxSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                HuxCountUp(
                  value: numeralValue!,
                  format: numeralFormat,
                  style: numeralStyle,
                ),
                Padding(
                  padding: const EdgeInsets.only(
                      left: HuxSpacing.xs, bottom: HuxSpacing.xs),
                  child: Text(unit, style: textTheme.bodySmall),
                ),
                if (delta != null) ...[
                  const SizedBox(width: HuxSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(bottom: HuxSpacing.xs),
                    child: delta!,
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: HuxSpacing.md),
          SizedBox(height: 160, child: child),
        ],
      ),
    );
  }
}

/// Bars per night, drawn as gradient pills over a faint full-height
/// slot track. A missing night keeps its slot but draws NO pill — the
/// empty track reads as "a night with no data", never as a zero.
class _SleepBarChart extends StatelessWidget {
  final List<NightRow> rows;
  final PersonalBaseline baseline;

  const _SleepBarChart({required this.rows, required this.baseline});

  /// Index of the most recent night WITH data — the one bar that gets
  /// the mint highlight (every other night is a misty grey pill, per
  /// the analytics-card reference).
  int? get _latestIndex {
    for (var i = rows.length - 1; i >= 0; i--) {
      if (rows[i].sleepDuration != null) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final band = SleepTargetBand.fromBaseline(baseline);
    final barWidth = rows.length > 14 ? 4.0 : 10.0;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    final highlightLabelStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: HuxColors.accentPink, fontWeight: FontWeight.w700);
    final targetStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: HuxColors.accentPink);
    final interval = _weekdayLabelInterval(rows.length);
    final latestIndex = _latestIndex;
    final median = baseline.medianTotalSleep;

    final hours = [
      for (final r in rows)
        if (r.sleepDuration != null) r.sleepDuration!.inMinutes / 60.0,
    ];
    final dataMax = hours.isEmpty ? 0.0 : hours.reduce((a, b) => a > b ? a : b);
    // Headroom above the tallest bar; floor of 8h so a short-sleep week
    // doesn't make its bars tower misleadingly.
    final maxY = (dataMax + 1).clamp(8.0, double.infinity);

    const greyBar = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [HuxColors.chartBarGreyBottom, HuxColors.chartBarGreyTop],
    );
    const mintBar = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [HuxColors.accentPurple, HuxColors.accentPink],
    );

    // Grow-in: tracks + target line appear immediately; the pills rise
    // from the baseline once (fl_chart's own lerp animates later range
    // swaps).
    return HuxChartGrowIn(
      builder: (context, t) => BarChart(
        swapAnimationDuration: HuxMotion.base,
        swapAnimationCurve: HuxMotion.easeSwap,
        BarChartData(
          maxY: maxY,
          barGroups: [
            for (var i = 0; i < rows.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: rows[i].sleepDuration == null
                      ? 0
                      : rows[i].sleepDuration!.inMinutes / 60.0 * t,
                  gradient: rows[i].sleepDuration == null
                      ? null
                      : (i == latestIndex ? mintBar : greyBar),
                  color:
                      rows[i].sleepDuration == null ? Colors.transparent : null,
                  width: barWidth,
                  borderRadius: BorderRadius.circular(barWidth / 2),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxY,
                    color: HuxColors.chartTrack,
                  ),
                ),
              ]),
          ],
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            show: true,
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= rows.length) {
                    return const SizedBox.shrink();
                  }
                  // The highlighted night always keeps its label (mint,
                  // like the reference's bold "Tue"); other slots thin
                  // out on the 30-day view.
                  final isLatest = i == latestIndex;
                  if (!isLatest && i % interval != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: HuxSpacing.xs),
                    child: Text(
                      _weekdayInitial(rows[i].night),
                      style: isLatest ? highlightLabelStyle : labelStyle,
                    ),
                  );
                },
              ),
            ),
          ),
          // The personal target, reference-style: a dashed mint line at
          // the user's own median with a small "Target" label, over the
          // (now fainter) ±10% band.
          extraLinesData: median == null
              ? const ExtraLinesData()
              : ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: median.inMinutes / 60.0,
                    color: HuxColors.accentPink
                        .withValues(alpha: HuxOpacity.targetLine),
                    strokeWidth: 1,
                    dashArray: HuxGlass.dashArray,
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: targetStyle,
                      labelResolver: (_) => 'Target ${_formatHours(median)}',
                    ),
                  ),
                ]),
          rangeAnnotations: band == null
              ? const RangeAnnotations()
              : RangeAnnotations(horizontalRangeAnnotations: [
                  HorizontalRangeAnnotation(
                    y1: band.low.inMinutes / 60.0,
                    y2: band.high.inMinutes / 60.0,
                    color: HuxColors.accentPink
                        .withValues(alpha: HuxOpacity.targetBand),
                  ),
                ]),
        ),
      ),
    );
  }
}

/// A line per contiguous run of nights with data — the gap between two
/// runs is genuinely empty space, never a line bridging over (which
/// would silently invent a reading for a night HUX never saw).
///
/// Reference-card treatment: a smooth curved line with a mint→teal
/// gradient stroke and a soft neon glow, a fading area fill beneath,
/// and a glowing halo dot on the most recent reading only.
class _MetricLineChart extends StatelessWidget {
  final List<NightRow> rows;
  final double? Function(NightRow) valueOf;

  const _MetricLineChart({required this.rows, required this.valueOf});

  @override
  Widget build(BuildContext context) {
    final runs = contiguousRuns(rows.map(valueOf).toList());
    if (runs.isEmpty) {
      return const Center(child: Text('No data in this range yet'));
    }

    // Grow-in: the line fades in while drifting up into place — data
    // is never scaled (that would warp the auto Y-range mid-flight).
    return HuxChartGrowIn(
      builder: (context, t) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, HuxMotion.slideDistance * (1 - t)),
          child: _chart(),
        ),
      ),
    );
  }

  Widget _chart() {
    final runs = contiguousRuns(rows.map(valueOf).toList());
    return LineChart(
        duration: HuxMotion.base,
        curve: HuxMotion.easeSwap,
        LineChartData(
          minX: 0,
          maxX: (rows.length - 1).clamp(0, double.infinity).toDouble(),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: const FlTitlesData(show: false),
          lineBarsData: [
            for (final run in runs)
              LineChartBarData(
                spots: [for (final e in run) FlSpot(e.key.toDouble(), e.value)],
                isCurved: true,
                preventCurveOverShooting: true,
                gradient: const LinearGradient(
                  colors: [HuxColors.accentPink, HuxColors.accentCherry],
                ),
                barWidth: 3,
                shadow: Shadow(
                  color: HuxColors.accentPink
                      .withValues(alpha: HuxOpacity.chartLineGlow),
                  blurRadius: HuxGlass.chartGlowBlur,
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      HuxColors.accentPink
                          .withValues(alpha: HuxOpacity.chartAreaFill),
                      Colors.transparent,
                    ],
                  ),
                ),
                // Only the latest reading of the latest run gets a dot —
                // a glowing "you are here" marker, not a dot per night.
                dotData: FlDotData(
                  show: identical(run, runs.last),
                  checkToShowDot: (spot, barData) => spot == barData.spots.last,
                  getDotPainter: (spot, percent, barData, index) =>
                      FlDotCirclePainter(
                    radius: HuxSpacing.xs,
                    color: HuxColors.accentPink,
                    strokeWidth: HuxSpacing.sm,
                    strokeColor: HuxColors.accentPink
                        .withValues(alpha: HuxOpacity.chartDotHalo),
                  ),
                ),
              ),
          ],
        ));
  }
}
