/// Trends screen — 7-day / 30-day sleep duration, HRV, and resting HR,
/// each night plotted from the user's own history: an at-a-glance row,
/// then one card per metric with its own colour, a vs-average chip,
/// a dashed average line and tap-for-value tooltips.
///
/// Talks only to [HealthStore.sleepSessionsBetween] — no snapshots, no
/// other services. Per-night rows come from the pure helper in
/// core/trends/night_row.dart; this file only charts them.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/meaning/baseline.dart';
import '../core/storage/health_store.dart';
import '../core/trends/night_row.dart';
import '../theme/hux_motion.dart';
import '../theme/hux_page.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';
import '../widgets/wellness_note.dart';

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

  /// Clock override for tests; null = the real time.
  final DateTime Function()? now;

  const TrendsScreen({super.key, required this.store, this.now});

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
    final now = (widget.now ?? DateTime.now)().toUtc();
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
                    if (snapshot.hasError) {
                      // Never an endless spinner: say so, offer a retry.
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text("Couldn't load your trends."),
                            TextButton(
                              onPressed: () => _onRangeChanged(_range),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }
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
      showSelectedIcon: false,
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
  Widget build(BuildContext context) => const Center(
        child: HuxEmptyState(
          icon: Icons.show_chart_rounded,
          color: HuxColors.ringSleep,
          title: 'Not enough data to show trends yet',
          body: 'Charts fill in as nights sync from your health app or ring.',
        ),
      );
}

/// Which way is "better" for a metric — colours the vs-average chip.
enum _Better { higher, lower, neither }

/// Everything a metric card needs besides the rows.
class _Metric {
  final String title;
  final IconData icon;
  final Color color;
  final String unit;
  final _Better better;
  final double? Function(NightRow) valueOf;

  const _Metric(this.title, this.icon, this.color, this.unit, this.better, this.valueOf);
}

double? _avgOf(List<NightRow> rows, double? Function(NightRow) valueOf) {
  final v = rows.map(valueOf).whereType<double>().toList();
  if (v.isEmpty) return null;
  return v.reduce((a, b) => a + b) / v.length;
}

/// Latest reading vs the range average, as a whole percent (null when
/// there's only one reading — nothing to compare against).
int? _vsAvgPct(List<NightRow> rows, double? Function(NightRow) valueOf) {
  final v = rows.map(valueOf).whereType<double>().toList();
  if (v.length < 2) return null;
  final avg = v.reduce((a, b) => a + b) / v.length;
  if (avg == 0) return null;
  return (((v.last - avg) / avg) * 100).round();
}

const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _dayLabel(DateTime d) => '${_weekdayShort[d.weekday - 1]} ${d.day}';

class _TrendsCharts extends StatelessWidget {
  final List<NightRow> rows;
  final PersonalBaseline baseline;

  const _TrendsCharts({required this.rows, required this.baseline});

  static final _metrics = <_Metric>[
    _Metric('Avg HRV', Icons.monitor_heart_outlined, HuxColors.accentPurple, 'ms', _Better.higher,
        (r) => r.avgHrvMs),
    _Metric('Avg resting heart rate', Icons.favorite_border_rounded, HuxColors.ringHeart, 'bpm', _Better.lower,
        (r) => r.avgHeartRateBpm),
    _Metric('Avg respiratory rate', Icons.air_rounded, HuxColors.steady, 'brpm', _Better.neither,
        (r) => r.avgRespiratoryRateBrpm),
    _Metric('Stress', Icons.spa_outlined, HuxColors.stretched, '/100', _Better.lower, (r) => r.avgStressIndex),
    _Metric('Active calories', Icons.local_fire_department_outlined, HuxColors.ringSteps, 'kcal', _Better.higher,
        (r) => r.activeEnergyKcal),
  ];

  @override
  Widget build(BuildContext context) {
    final latestSleep = _latestOf(rows, (r) => r.sleepDuration?.inMinutes.toDouble());

    // The sleep delta chip: latest night vs the user's own baseline
    // median — never a population number.
    final medianMinutes = baseline.medianTotalSleep?.inMinutes.toDouble();
    int? sleepDeltaPct;
    if (latestSleep != null && medianMinutes != null && medianMinutes > 0) {
      sleepDeltaPct = (((latestSleep - medianMinutes) / medianMinutes) * 100).round();
    }

    final avgSleep = _avgOf(rows, (r) => r.sleepDuration?.inMinutes.toDouble());
    final avgHrv = _avgOf(rows, (r) => r.avgHrvMs);
    final avgHr = _avgOf(rows, (r) => r.avgHeartRateBpm);
    final nights = rows.where((r) => r.sleepDuration != null).length;

    return ListView(
      // Clearance so the last chart scrolls clear of the floating nav bar.
      padding: const EdgeInsets.only(bottom: HuxGlass.navClearance),
      children: [
        // ---- at a glance: one compact row (keeps the charts high up) ----
        HuxEntrance(
          child: HuxCard(
            padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.sm, vertical: HuxSpacing.md),
            child: Row(
              children: [
                _Glance(
                    label: 'Sleep',
                    value: avgSleep == null ? '—' : _formatHours(Duration(minutes: avgSleep.round())),
                    color: HuxColors.ringSleep),
                _Glance(label: 'HRV', value: avgHrv == null ? '—' : '${avgHrv.round()}', color: HuxColors.accentPurple),
                _Glance(label: 'Rest HR', value: avgHr == null ? '—' : '${avgHr.round()}', color: HuxColors.ringHeart),
                _Glance(label: 'Nights', value: '$nights/${rows.length}', color: HuxColors.ringFood),
              ],
            ),
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 1,
          child: _ChartCard(
            title: 'Sleep duration',
            icon: Icons.bedtime_outlined,
            color: HuxColors.ringSleep,
            numeralValue: latestSleep,
            numeralFormat: (v) => _formatHours(Duration(minutes: v.round())),
            unit: 'hrs',
            delta: sleepDeltaPct == null
                ? null
                : _DeltaChip(percent: sleepDeltaPct, better: _Better.higher, suffix: 'vs usual'),
            child: _SleepBarChart(rows: rows, baseline: baseline),
          ),
        ),
        for (final (i, m) in _metrics.indexed) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(
            index: 2 + i,
            child: _ChartCard(
              title: m.title,
              icon: m.icon,
              color: m.color,
              numeralValue: _latestOf(rows, m.valueOf),
              numeralFormat: (v) => v.round().toString(),
              unit: m.unit,
              hint: _minMaxHint(rows, m.valueOf, m.unit),
              delta: switch (_vsAvgPct(rows, m.valueOf)) {
                null => null,
                final pct => _DeltaChip(percent: pct, better: m.better, suffix: 'vs avg'),
              },
              child: _MetricLineChart(rows: rows, valueOf: m.valueOf, color: m.color, unit: m.unit),
            ),
          ),
        ],
        const WellnessNote(),
      ],
    );
  }
}

/// One averaged number in the at-a-glance row.
class _Glance extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Glance({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: text.labelSmall?.copyWith(color: HuxColors.mutedText)),
        ],
      ),
    );
  }
}

/// "↑ 6% vs usual" — green when the change is the good direction for
/// this metric, amber when not, grey for metrics with no better side.
/// Wellness register: it compares to "your usual", it never judges.
class _DeltaChip extends StatelessWidget {
  final int percent;
  final _Better better;
  final String suffix;

  const _DeltaChip({required this.percent, required this.better, required this.suffix});

  @override
  Widget build(BuildContext context) {
    final up = percent >= 0;
    final good = switch (better) {
      _Better.higher => up,
      _Better.lower => !up,
      _Better.neither => null,
    };
    final color = percent == 0 || good == null
        ? HuxColors.mutedText
        : (good ? HuxColors.recharged : HuxColors.stretched);
    return HuxPill(
      label: '${up ? '↑' : '↓'} ${percent.abs()}% $suffix',
      color: color,
    );
  }
}

/// One chart card: coloured icon + title (with min–max hint), a big
/// numeral counting up to the most recent reading plus a vs-average
/// chip, then the chart itself.
class _ChartCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final double? numeralValue;
  final String Function(double) numeralFormat;
  final String unit;
  final String? hint;
  final Widget? delta;
  final Widget child;

  const _ChartCard({
    required this.title,
    required this.icon,
    required this.color,
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

    return HuxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HuxIconBadge(icon: icon, color: color, size: 32),
              const SizedBox(width: HuxSpacing.sm),
              Expanded(
                child: Text(title, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              if (hint != null) Text(hint!, style: textTheme.labelSmall?.copyWith(color: HuxColors.mutedText)),
            ],
          ),
          if (numeralValue != null) ...[
            const SizedBox(height: HuxSpacing.sm),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: HuxSpacing.sm,
              runSpacing: HuxSpacing.xs,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    HuxCountUp(value: numeralValue!, format: numeralFormat, style: numeralStyle),
                    Padding(
                      padding: const EdgeInsets.only(left: HuxSpacing.xs, bottom: HuxSpacing.xs),
                      child: Text(unit, style: textTheme.bodySmall?.copyWith(color: HuxColors.mutedText)),
                    ),
                  ],
                ),
                if (delta != null)
                  Padding(padding: const EdgeInsets.only(bottom: HuxSpacing.xs), child: delta!),
              ],
            ),
          ],
          const SizedBox(height: HuxSpacing.md),
          SizedBox(height: 170, child: child),
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
        ?.copyWith(color: HuxColors.ringSleep, fontWeight: FontWeight.w700);
    final targetStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: HuxColors.ringSleep, fontWeight: FontWeight.w600);
    final tooltipStyle = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(color: HuxColors.onVivid, fontWeight: FontWeight.w600);
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
    final mintBar = LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [HuxColors.ringSleep.withValues(alpha: 0.7), HuxColors.ringSleep],
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
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipBgColor: HuxColors.ink,
              tooltipRoundedRadius: HuxSpacing.sm,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final row = rows[group.x];
                final d = row.sleepDuration;
                if (d == null) return null;
                return BarTooltipItem(
                  '${_dayLabel(row.night)}\n${_formatHours(d)} h',
                  tooltipStyle ?? const TextStyle(),
                );
              },
            ),
          ),
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
                    color: HuxColors.ringSleep
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
                    color: HuxColors.ringSleep
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
  final Color color;
  final String unit;

  const _MetricLineChart({required this.rows, required this.valueOf, required this.color, required this.unit});

  @override
  Widget build(BuildContext context) {
    final runs = contiguousRuns(rows.map(valueOf).toList());
    if (runs.isEmpty) {
      return Center(
        child: Text('No data in this range yet',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: HuxColors.mutedText)),
      );
    }

    // Grow-in: the line fades in while drifting up into place — data
    // is never scaled (that would warp the auto Y-range mid-flight).
    return HuxChartGrowIn(
      builder: (context, t) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, HuxMotion.slideDistance * (1 - t)),
          child: _chart(context, runs),
        ),
      ),
    );
  }

  Widget _chart(BuildContext context, List<List<MapEntry<int, double>>> runs) {
    final text = Theme.of(context).textTheme;
    final labelStyle = text.labelSmall?.copyWith(color: HuxColors.mutedText);
    final tooltipStyle = text.labelMedium?.copyWith(color: HuxColors.onVivid, fontWeight: FontWeight.w600);
    final interval = _weekdayLabelInterval(rows.length);
    final avg = _avgOf(rows, valueOf);

    return LineChart(
        duration: HuxMotion.base,
        curve: HuxMotion.easeSwap,
        LineChartData(
          minX: 0,
          maxX: (rows.length - 1).clamp(0, double.infinity).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => const FlLine(color: HuxColors.hairline, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 20,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (value != i.toDouble() || i < 0 || i >= rows.length) return const SizedBox.shrink();
                  final isLast = i == rows.length - 1;
                  if (!isLast && i % interval != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: HuxSpacing.xs),
                    child: Text(_weekdayInitial(rows[i].night),
                        style: isLast ? labelStyle?.copyWith(color: color, fontWeight: FontWeight.w700) : labelStyle),
                  );
                },
              ),
            ),
          ),
          // Your average for this range, as a faint dashed reference.
          extraLinesData: avg == null
              ? const ExtraLinesData()
              : ExtraLinesData(horizontalLines: [
                  HorizontalLine(
                    y: avg,
                    color: color.withValues(alpha: 0.45),
                    strokeWidth: 1,
                    dashArray: HuxGlass.dashArray,
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      style: labelStyle?.copyWith(color: color, fontWeight: FontWeight.w600),
                      labelResolver: (_) => 'Avg ${avg.round()}',
                    ),
                  ),
                ]),
          lineTouchData: LineTouchData(
            getTouchedSpotIndicator: (barData, indexes) => [
              for (final _ in indexes)
                TouchedSpotIndicatorData(
                  FlLine(color: color.withValues(alpha: 0.35), strokeWidth: 1, dashArray: HuxGlass.dashArray),
                  FlDotData(
                    getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                      radius: 5,
                      color: HuxColors.card,
                      strokeWidth: 3,
                      strokeColor: color,
                    ),
                  ),
                ),
            ],
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: HuxColors.ink,
              tooltipRoundedRadius: HuxSpacing.sm,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${_dayLabel(rows[s.x.round()].night)}\n${s.y.round()} $unit',
                    tooltipStyle ?? const TextStyle(),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            for (final run in runs)
              LineChartBarData(
                spots: [for (final e in run) FlSpot(e.key.toDouble(), e.value)],
                isCurved: true,
                preventCurveOverShooting: true,
                gradient: LinearGradient(colors: [color.withValues(alpha: 0.55), color]),
                barWidth: 3,
                isStrokeCapRound: true,
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
                  ),
                ),
                // Only the latest reading of the latest run gets a dot —
                // a "you are here" marker, not a dot per night.
                dotData: FlDotData(
                  show: identical(run, runs.last),
                  checkToShowDot: (spot, barData) => spot == barData.spots.last,
                  getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                    radius: 5,
                    color: color,
                    strokeWidth: 3,
                    strokeColor: HuxColors.card,
                  ),
                ),
              ),
          ],
        ));
  }
}
