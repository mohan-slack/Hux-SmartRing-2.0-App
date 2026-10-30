/// HUX UI 2.0 component kit — the eight parts every redesigned screen
/// is built from (see the "HUX UI Redesign" canvas, Component kit).
///
/// Rules: one hero per screen; a tile = a 2-word label, one number and
/// a shape that draws its own data; sentence case; explanations live in
/// sheets, never on the card.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/hux_tokens.dart';

/// Night plum: the only dark surface, behind the Charge ring.
const huxNight = Color(0xFF1C0D30);
const huxNightTrack = Color(0xFF33244A);
const huxNightMuted = Color(0xFFBFB1D3);
const huxTileBg = Color(0xFFFFFFFF);
const huxTrack = Color(0xFFEFEDF5);
const huxInk = Color(0xFF1B1925);
const huxMuted = Color(0xFF5F5A6E);

const huxChargeGradient = [Color(0xFFFF8FCB), Color(0xFFF567B5), Color(0xFFC93B86), Color(0xFF8B3FD0), Color(0xFF5B6CF0)];

TextStyle _num(double size, {Color color = huxInk}) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// A white tile: radius 20, no shadow. Tappable when [onTap] is set.
class HuxTile extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  const HuxTile({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(16), this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final body = Material(
      color: huxTileBg,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    return semanticLabel == null ? body : Semantics(label: semanticLabel, button: onTap != null, child: body);
  }
}

/// The tile's label: sentence case, 15/700, muted.
class HuxTileLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const HuxTileLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxMuted));
    if (trailing == null) return label;
    return Row(children: [Expanded(child: label), trailing!]);
  }
}

/// The big number on a tile, with an optional small unit.
class HuxTileValue extends StatelessWidget {
  final String value;
  final String? unit;
  final double size;

  const HuxTileValue(this.value, {super.key, this.unit, this.size = 28});

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(text: value, style: _num(size)),
          if (unit != null)
            TextSpan(text: ' $unit', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: huxMuted)),
        ]),
      );
}

// ---------------------------------------------------------------------------
// 1 · Charge orb
// ---------------------------------------------------------------------------

/// The Charge ring: arc grows clockwise from 12 o'clock with the charge,
/// ending in the pearl ("now"). Value in the middle.
class HuxChargeOrb extends StatelessWidget {
  final int? value;
  final double size;
  final String caption;
  final bool onDark;

  const HuxChargeOrb({super.key, required this.value, this.size = 148, this.caption = 'Charge', this.onDark = true});

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? Colors.white : huxInk;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _OrbPainter(progress: (value ?? 0) / 100, track: onDark ? huxNightTrack : huxTrack, stroke: size * 0.08),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value == null ? '—' : '$value', style: _num(size * 0.36, color: fg)),
              const SizedBox(height: 2),
              Text(caption,
                  style: TextStyle(fontSize: math.max(12, size * 0.095), color: onDark ? huxNightMuted : huxMuted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double progress;
  final Color track;
  final double stroke;

  _OrbPainter({required this.progress, required this.track, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - stroke / 2 - 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);
    final p = progress.clamp(0.0, 1.0);
    if (p <= 0) return;
    final sweep = math.pi * 2 * p;
    final shader = SweepGradient(
      colors: huxChargeGradient,
      endAngle: math.max(sweep, 0.01),
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = shader);
    final end = Offset(c.dx + r * math.cos(-math.pi / 2 + sweep), c.dy + r * math.sin(-math.pi / 2 + sweep));
    canvas.drawCircle(end, stroke * 0.75, Paint()
      ..color = const Color(0x8CFFD6EE)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, stroke * 0.6));
    canvas.drawCircle(end, stroke * 0.55, Paint()..color = const Color(0xFFFFF4FA));
  }

  @override
  bool shouldRepaint(_OrbPainter o) => o.progress != progress || o.track != track;
}

// ---------------------------------------------------------------------------
// 2 · Stat chip
// ---------------------------------------------------------------------------

enum HuxTone { neutral, good, watch }

class HuxStatChip extends StatelessWidget {
  final String label;
  final HuxTone tone;
  final bool onDark;

  const HuxStatChip(this.label, {super.key, this.tone = HuxTone.neutral, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = onDark
        ? (const Color(0xFF2E1E45), Colors.white)
        : switch (tone) {
            HuxTone.good => (const Color(0xFFE3F5EA), const Color(0xFF17804B)),
            HuxTone.watch => (const Color(0xFFFDF1DE), const Color(0xFF8A5100)),
            HuxTone.neutral => (const Color(0xFFF1EEF7), const Color(0xFF3A3646)),
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

// ---------------------------------------------------------------------------
// 3 · Sparkline, segment bar, hour bars
// ---------------------------------------------------------------------------

class HuxSparkline extends StatelessWidget {
  final List<num?> values;
  final Color color;
  final double height;

  const HuxSparkline({super.key, required this.values, required this.color, this.height = 28});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _SparkPainter(values, color)));
}

class _SparkPainter extends CustomPainter {
  final List<num?> values;
  final Color color;

  _SparkPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <Offset>[];
    final known = values.whereType<num>().toList();
    if (known.length < 2) return;
    final lo = known.reduce(math.min).toDouble(), hi = known.reduce(math.max).toDouble();
    final span = math.max(hi - lo, 4.0); // a flat week stays flat, not noisy
    final mid = (hi + lo) / 2;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = values.length == 1 ? 0.0 : i / (values.length - 1) * (size.width - 6) + 3;
      final y = size.height / 2 - (v - mid) / span * (size.height - 8);
      pts.add(Offset(x, y));
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = color);
    canvas.drawCircle(pts.last, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.values != values || o.color != color;
}

/// Progress as N blocks (portions), the last one partly filled.
class HuxSegmentBar extends StatelessWidget {
  final double value;
  final double max;
  final int segments;
  final Color color;

  const HuxSegmentBar({super.key, required this.value, required this.max, this.segments = 6, required this.color});

  @override
  Widget build(BuildContext context) {
    final filled = max <= 0 ? 0.0 : (value / max * segments).clamp(0.0, segments.toDouble());
    return Row(
      children: [
        for (var i = 0; i < segments; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 12,
                child: LinearProgressIndicator(
                  value: (filled - i).clamp(0.0, 1.0),
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.15),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Small vertical bars (e.g. steps per hour); the biggest is solid.
class HuxHourBars extends StatelessWidget {
  final List<int> values;
  final int slots;
  final Color color;
  final double height;

  const HuxHourBars({super.key, required this.values, this.slots = 12, required this.color, this.height = 34});

  @override
  Widget build(BuildContext context) {
    final shown = values.length > slots ? values.sublist(values.length - slots) : values;
    final peak = shown.isEmpty ? 0 : shown.reduce(math.max);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < slots; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: i >= shown.length || peak == 0
                    ? height * 0.08
                    : math.max(height * 0.08, height * shown[i] / peak),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: i >= shown.length || shown[i] == 0
                      ? huxTrack
                      : (shown[i] == peak ? color : color.withValues(alpha: 0.45)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4 · Sleep window and bedtime week (axis 9 PM → 9 AM)
// ---------------------------------------------------------------------------

double _nightFraction(DateTime t) {
  final m = ((t.hour * 60 + t.minute) - 21 * 60 + 24 * 60) % (24 * 60);
  return (m / (12 * 60)).clamp(0.0, 1.0);
}

String huxClock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')}';
}

/// Last night on a 9 PM–9 AM line, target bedtime window dashed.
class HuxSleepWindow extends StatelessWidget {
  final DateTime bed;
  final DateTime wake;
  final DateTime? targetBed;
  final Color color;

  const HuxSleepWindow({super.key, required this.bed, required this.wake, this.targetBed, this.color = HuxColors.ringSleep});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Asleep ${huxClock(bed)} to ${huxClock(wake)}',
          child: SizedBox(
            height: 18,
            child: CustomPaint(painter: _WindowPainter(_nightFraction(bed), _nightFraction(wake),
                targetBed == null ? null : _nightFraction(targetBed!), _nightFraction(wake), color)),
          ),
        ),
        const SizedBox(height: 6),
        DefaultTextStyle(
          style: const TextStyle(fontSize: 13, color: huxMuted),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [const Text('9 PM'), Text('${huxClock(bed)} → ${huxClock(wake)}'), const Text('9 AM')],
          ),
        ),
      ],
    );
  }
}

class _WindowPainter extends CustomPainter {
  final double from, to;
  final double? targetFrom, targetTo;
  final Color color;

  _WindowPainter(this.from, this.to, this.targetFrom, this.targetTo, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = huxTrack);
    if (targetFrom != null && targetTo != null && targetTo! > targetFrom!) {
      final t = Rect.fromLTRB(size.width * targetFrom!, 1, size.width * targetTo!, size.height - 1);
      _dashedRRect(canvas, RRect.fromRectAndRadius(t, r), color.withValues(alpha: 0.45));
    }
    if (to > from) {
      final s = Rect.fromLTRB(size.width * from, 3, size.width * to, size.height - 3);
      canvas.drawRRect(RRect.fromRectAndRadius(s, const Radius.circular(6)), Paint()..color = color);
    }
  }

  void _dashedRRect(Canvas canvas, RRect rr, Color c) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = c;
    for (final metric in (Path()..addRRect(rr)).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 4, metric.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_WindowPainter o) => o.from != from || o.to != to || o.targetFrom != targetFrom;
}

/// Seven nights as floating bars, bed (top) to wake (bottom), with the
/// target bedtime as a dashed line. Today's night is solid.
class HuxBedtimeWeek extends StatelessWidget {
  final List<({DateTime bed, DateTime wake})?> nights;
  final DateTime? targetBed;
  final Color color;

  const HuxBedtimeWeek({super.key, required this.nights, this.targetBed, this.color = HuxColors.ringSleep});

  static const _days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final labels = [for (var i = 6; i >= 0; i--) _days[now.subtract(Duration(days: i)).weekday - 1]];
    const h = 120.0;
    return Semantics(
      label: 'Bedtimes for the last ${nights.length} nights',
      child: Column(
        children: [
          SizedBox(
            height: h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  child: Stack(
                    children: [
                      const Positioned(top: 0, child: Text('9 PM', style: TextStyle(fontSize: 12, color: huxMuted))),
                      if (targetBed != null)
                        Positioned(
                          top: (h * _nightFraction(targetBed!) - 7).clamp(14.0, h - 30),
                          child: Text(huxClock(targetBed!),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                        ),
                      const Positioned(bottom: 0, child: Text('9 AM', style: TextStyle(fontSize: 12, color: huxMuted))),
                    ],
                  ),
                ),
                Expanded(
                  child: CustomPaint(
                    size: const Size(double.infinity, h),
                    painter: _WeekPainter(nights, targetBed == null ? null : _nightFraction(targetBed!), color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 44),
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Text(labels[i],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: i == labels.length - 1 ? FontWeight.w800 : FontWeight.w500,
                          color: i == labels.length - 1 ? huxInk : huxMuted)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WeekPainter extends CustomPainter {
  final List<({DateTime bed, DateTime wake})?> nights;
  final double? target;
  final Color color;

  _WeekPainter(this.nights, this.target, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (target != null) {
      final y = size.height * target!;
      final p = Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = 2;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), p);
      }
    }
    final n = nights.length;
    if (n == 0) return;
    final slot = size.width / n;
    final w = slot * 0.6;
    for (var i = 0; i < n; i++) {
      final night = nights[i];
      if (night == null) continue;
      final top = size.height * _nightFraction(night.bed);
      final bottom = size.height * _nightFraction(night.wake);
      if (bottom <= top) continue;
      final x = slot * i + (slot - w) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(x, top, x + w, bottom), const Radius.circular(6)),
        Paint()..color = i == n - 1 ? color : color.withValues(alpha: 0.32),
      );
    }
  }

  @override
  bool shouldRepaint(_WeekPainter o) => o.nights != nights || o.target != target;
}

// ---------------------------------------------------------------------------
// 5 · Day line (6 AM → midnight), list fallback for large text
// ---------------------------------------------------------------------------

class HuxDayEvent {
  final int minuteOfDay;
  final String label;
  final Color color;
  final bool done;

  /// Shown instead of the computed clock (e.g. a bedtime after midnight
  /// pinned to the end of the line).
  final String? time;

  const HuxDayEvent({required this.minuteOfDay, required this.label, required this.color, this.done = false, this.time});

  String get text => '$label ${time ?? HuxDayLine.clock(minuteOfDay)}';
}

class HuxDayLine extends StatelessWidget {
  final List<HuxDayEvent> events;
  final int nowMinute;

  const HuxDayLine({super.key, required this.events, required this.nowMinute});

  static const _start = 6 * 60, _end = 24 * 60;

  static String clock(int m) {
    final h = (m ~/ 60) % 24;
    final hh = h % 12 == 0 ? 12 : h % 12;
    final mm = m % 60;
    return mm == 0 ? '$hh' : '$hh:${mm.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...events]..sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));
    // Big text: labels would collide on a line, so show a short list.
    if (MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3) {
      return Column(
        children: [
          for (final e in sorted)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: e.color, shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Text(e.time ?? clock(e.minuteOfDay), style: _num(16)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e.label, style: TextStyle(fontSize: 16, color: e.done ? huxMuted : huxInk))),
                ],
              ),
            ),
        ],
      );
    }
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double x(int m) => ((m.clamp(_start, _end) - _start) / (_end - _start)) * w;
      double measure(String t, TextStyle st) =>
          (TextPainter(text: TextSpan(text: t, style: st), textDirection: TextDirection.ltr, textScaler: scaler)
                ..layout())
              .width;

      final nowX = x(nowMinute);
      const nowStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: huxInk);
      final nowW = measure('Now', nowStyle);
      final nowLeft = (nowX - nowW / 2).clamp(0.0, math.max(0.0, w - nowW)).toDouble();

      // Two label rows (above / below the line). Each label goes where
      // it doesn't touch another; if neither row has room, the dot stays
      // unlabeled (the semantics label and big-text list still name it).
      const gap = 10.0;
      final rows = <List<(double, double)>>[
        [(nowLeft, nowLeft + nowW)], // above: "Now" owns its spot
        [], // below
      ];
      bool free(int row, double a, double b) => rows[row].every((r) => b + gap <= r.$1 || a >= r.$2 + gap);

      final children = <Widget>[
        Positioned(left: 0, right: 0, top: 38, child: Container(height: 2, color: const Color(0xFFE6E2EC))),
        Positioned(
            left: 0,
            top: 37,
            child: Container(
                width: nowX, height: 4, decoration: BoxDecoration(color: huxInk, borderRadius: BorderRadius.circular(2)))),
        Positioned(left: nowX - 1, top: 28, child: Container(width: 2, height: 22, color: huxInk)),
        Positioned(left: nowLeft, top: 6, child: const Text('Now', style: nowStyle)),
      ];

      // Upcoming events first, so they win the label space.
      final order = [
        ...sorted.where((e) => e.minuteOfDay >= nowMinute),
        ...sorted.where((e) => e.minuteOfDay < nowMinute).toList().reversed,
      ];
      for (final e in order) {
        final ex = x(e.minuteOfDay);
        final past = e.minuteOfDay < nowMinute || e.done;
        children.add(Positioned(
          left: ex - 6,
          top: 33,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: past ? huxInk : Colors.white,
              border: Border.all(color: past ? huxInk : e.color, width: 3),
            ),
          ),
        ));
        final style = TextStyle(fontSize: 13, fontWeight: past ? FontWeight.w500 : FontWeight.w700, color: past ? huxMuted : huxInk);
        final tw = measure(e.text, style);
        final left = (ex - tw / 2).clamp(0.0, math.max(0.0, w - tw)).toDouble();
        final row = free(1, left, left + tw) ? 1 : (free(0, left, left + tw) ? 0 : -1);
        if (row < 0) continue;
        rows[row].add((left, left + tw));
        children.add(Positioned(
          top: row == 1 ? 54 : 6,
          left: left,
          child: Text(e.text, maxLines: 1, softWrap: false, style: style),
        ));
      }
      return Semantics(
        label: [for (final e in sorted) e.text].join(', '),
        excludeSemantics: true,
        child: SizedBox(height: 74, child: Stack(clipBehavior: Clip.none, children: children)),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// 6 · Next up, 7 · Program pill
// ---------------------------------------------------------------------------

class HuxNextUp extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onAction;

  const HuxNextUp({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.actionLabel = 'Start',
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return HuxTile(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: huxInk)),
                Text(subtitle, style: const TextStyle(fontSize: 15, color: huxMuted)),
              ],
            ),
          ),
          if (onAction != null)
            FilledButton(
              onPressed: onAction,
              style: FilledButton.styleFrom(
                backgroundColor: huxInk,
                foregroundColor: Colors.white,
                minimumSize: const Size(76, 44),
                shape: const StadiumBorder(),
              ),
              child: Text(actionLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

class HuxProgramPill extends StatelessWidget {
  final double progress;
  final String center;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const HuxProgramPill({
    super.key,
    required this.progress,
    required this.center,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return HuxTile(
      onTap: onTap,
      semanticLabel: '$title, $subtitle',
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      strokeWidth: 5,
                      color: color,
                      backgroundColor: huxTrack,
                    ),
                  ),
                  Text(center, style: _num(12)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxInk)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: huxMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
