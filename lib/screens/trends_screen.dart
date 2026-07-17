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
    final baseline = PersonalBaseline.fromSleepSessions([
      for (final s in sessions)
        if (!s.bedtime.toUtc().isBefore(baselineStart)) s,
    ]);
    final rows = buildNightRows(from: displayStart, to: now, sessions: sessions);

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
                      return const Center(
                          child: CircularProgressIndicator());
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
    return ListView(
      children: [
        _ChartCard(
          title: 'Sleep duration',
          child: _SleepBarChart(rows: rows, baseline: baseline),
        ),
        const SizedBox(height: HuxSpacing.xl),
        _ChartCard(
          title: 'Avg HRV',
          hint: _minMaxHint(rows, (r) => r.avgHrvMs, 'ms'),
          child: _MetricLineChart(rows: rows, valueOf: (r) => r.avgHrvMs),
        ),
        const SizedBox(height: HuxSpacing.xl),
        _ChartCard(
          title: 'Avg resting heart rate',
          hint: _minMaxHint(rows, (r) => r.avgHeartRateBpm, 'bpm'),
          child: _MetricLineChart(
              rows: rows, valueOf: (r) => r.avgHeartRateBpm),
        ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget child;

  const _ChartCard({required this.title, this.hint, required this.child});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(title, style: textTheme.labelLarge),
            if (hint != null) ...[
              const Spacer(),
              Text(hint!, style: textTheme.bodySmall),
            ],
          ],
        ),
        const SizedBox(height: HuxSpacing.sm),
        SizedBox(height: 160, child: child),
      ],
    );
  }
}

/// Bars per night. A missing night still occupies its slot (an
/// invisible, zero-color rod) so the timeline doesn't silently
/// compress — it just shows nothing there, never a visible zero.
class _SleepBarChart extends StatelessWidget {
  final List<NightRow> rows;
  final PersonalBaseline baseline;

  const _SleepBarChart({required this.rows, required this.baseline});

  @override
  Widget build(BuildContext context) {
    final band = SleepTargetBand.fromBaseline(baseline);
    const barColor = HuxColors.accentDeepTeal;
    final barWidth = rows.length > 14 ? 4.0 : 10.0;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    final interval = _weekdayLabelInterval(rows.length);

    return BarChart(BarChartData(
      barGroups: [
        for (var i = 0; i < rows.length; i++)
          BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY: rows[i].sleepDuration == null
                  ? 0
                  : rows[i].sleepDuration!.inMinutes / 60.0,
              color: rows[i].sleepDuration == null
                  ? Colors.transparent
                  : barColor,
              width: barWidth,
            ),
          ]),
      ],
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        show: true,
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 18,
            getTitlesWidget: (value, meta) {
              final i = value.round();
              if (i < 0 || i >= rows.length || i % interval != 0) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(top: HuxSpacing.xs),
                child:
                    Text(_weekdayInitial(rows[i].night), style: labelStyle),
              );
            },
          ),
        ),
      ),
      rangeAnnotations: band == null
          ? const RangeAnnotations()
          : RangeAnnotations(horizontalRangeAnnotations: [
              HorizontalRangeAnnotation(
                y1: band.low.inMinutes / 60.0,
                y2: band.high.inMinutes / 60.0,
                color:
                    HuxColors.accentMint.withValues(alpha: HuxOpacity.targetBand),
              ),
            ]),
    ));
  }
}

/// A line per contiguous run of nights with data — the gap between two
/// runs is genuinely empty space, never a line bridging over (which
/// would silently invent a reading for a night HUX never saw).
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

    const lineColor = HuxColors.accentDeepTeal;
    return LineChart(LineChartData(
      minX: 0,
      maxX: (rows.length - 1).clamp(0, double.infinity).toDouble(),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: const FlTitlesData(show: false),
      lineBarsData: [
        for (final run in runs)
          LineChartBarData(
            spots: [for (final e in run) FlSpot(e.key.toDouble(), e.value)],
            color: lineColor,
            barWidth: 2,
            dotData: const FlDotData(),
          ),
      ],
    ));
  }
}
