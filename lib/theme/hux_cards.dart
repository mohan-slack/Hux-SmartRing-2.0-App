/// HUX Cards
/// -----------
/// A small catalog of reusable stat-presentation cards beyond the plain
/// numeral tiles in today_screen.dart/trends_screen.dart: circular gauges,
/// a range slider, a two-value radial split, a bar visualizer, and a
/// "nudge" modal wired to a real ring action.
///
/// Built entirely on the existing design system (HuxColors/HuxSpacing/
/// HuxMotion) — no new dependencies. SECOND design pass: these cards
/// moved from [GlassPanel] (translucent) to [_SolidCardShell] (solid
/// near-black or accent-tinted fill), matching the app's move away from
/// glass toward solid/gradient cards — see hux_tokens.dart's file header.
/// The circular/radial shapes are the first hand-drawn Canvas work in
/// this codebase (every chart elsewhere goes through fl_chart); see
/// [_ArcGaugePainter]'s doc comment for why.
///
/// NULL RULE (same as _DisplayStatTile in today_screen.dart): a null
/// value must never render as if it were a confirmed zero. Each widget's
/// doc comment below spells out exactly what its null case looks like.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hux_glass.dart';
import 'hux_motion.dart';
import 'hux_tokens.dart';

/// The shared solid-fill shell every card in this file sits on —
/// replaces [GlassPanel] for this catalog (see file header). [frosted]
/// keeps its old meaning of "promote to the elevated surface," just
/// without translucency: false uses [HuxColors.card], true
/// [HuxColors.cardElevated]. Every card gets a decorative
/// [HuxGlassCorner] sheen and lifts on hover via [HuxHoverLift] — THIRD
/// design detail pass, layered on top of the second (solid-fill) one.
class _SolidCardShell extends StatelessWidget {
  final Widget child;
  final bool frosted;
  final Color? tint;

  const _SolidCardShell({required this.child, this.frosted = false, this.tint});

  static final _radius = BorderRadius.circular(HuxRadii.vividCard);

  @override
  Widget build(BuildContext context) {
    return HuxHoverLift(
      borderRadius: _radius,
      child: ClipRRect(
        borderRadius: _radius,
        child: Container(
          padding: const EdgeInsets.all(HuxSpacing.lg),
          decoration: BoxDecoration(
            color: tint ?? (frosted ? HuxColors.cardElevated : HuxColors.card),
          ),
          child: Stack(
            children: [
              child,
              HuxGlassCorner(borderRadius: _radius),
            ],
          ),
        ),
      ),
    );
  }
}

/// A dumb, stateless "draw whatever progress you're given" painter — no
/// [AnimationController] here. The one-shot grow-in animation lives in
/// the widgets above ([HuxChartGrowIn]'s existing 0→1 builder), matching
/// every other chart in this app rather than inventing a second
/// animation approach. `-pi/2` starts the arc at 12 o'clock; positive
/// sweep is clockwise (Flutter's native `drawArc` convention). A solid
/// accent color is used for the progress arc rather than a gradient —
/// a `SweepGradient` on a partial stroke shows a visible seam at the
/// arc's start/end, so this instead matches the delta-chip precedent of
/// one solid color per state.
class _ArcGaugePainter extends CustomPainter {
  final double progress; // 0..1, pre-clamped
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  const _ArcGaugePainter({
    required this.progress,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi, false, trackPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = progressColor;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress.clamp(0.0, 1.0), false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ArcGaugePainter oldDelegate) =>
      progress != oldDelegate.progress ||
      strokeWidth != oldDelegate.strokeWidth ||
      trackColor != oldDelegate.trackColor ||
      progressColor != oldDelegate.progressColor;
}

enum HeroGaugeLabelPosition { above, below }

/// A single circular ring gauge with a big centered numeral — e.g. ring
/// battery percent. Lives inside a [_SolidCardShell] (the ring is
/// content, not a card-chrome replacement).
///
/// NULL: renders the grey track only (no progress arc drawn at all), the
/// center shows a plain em-dash in the numeral's own [TextStyle] (so
/// layout doesn't jump when a real value arrives), and the unit is
/// hidden alongside it — the same convention `_DisplayStatTile` already
/// uses in today_screen.dart, ported to a gauge.
class HeroGaugeCard extends StatelessWidget {
  final String label;
  final double? value;
  final double max;
  final String? unit;
  final String Function(double)? format;
  final double size;
  final double strokeWidth;
  final Color accentColor;
  final HeroGaugeLabelPosition labelPosition;
  final bool frosted;

  /// The card's background tint — separate from [accentColor] (the arc
  /// stroke), so a card can sit in one color family (e.g. Athens Indigo
  /// for a device/connectivity card) while its arc stays a brighter,
  /// more legible color. Defaults to a subtle tint of [accentColor]
  /// itself when not given.
  final Color? cardTint;

  const HeroGaugeCard({
    super.key,
    required this.label,
    required this.value,
    this.max = 100,
    this.unit,
    this.format,
    this.size = 140,
    this.strokeWidth = 14,
    this.accentColor = HuxColors.accentPink,
    this.labelPosition = HeroGaugeLabelPosition.above,
    this.frosted = false,
    this.cardTint,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final numeralStyle = textTheme.titleLarge?.copyWith(
      fontSize: HuxType.numeral,
      fontWeight: FontWeight.w700,
    );
    final labelWidget = Text(label, style: textTheme.bodySmall);
    final targetFraction = value == null ? 0.0 : (value! / max).clamp(0.0, 1.0);

    return _SolidCardShell(
      frosted: frosted,
      tint: Color.alphaBlend((cardTint ?? accentColor).withValues(alpha: 0.28), HuxColors.card),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (labelPosition == HeroGaugeLabelPosition.above) ...[
            labelWidget,
            const SizedBox(height: HuxSpacing.sm),
          ],
          SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                HuxChartGrowIn(
                  builder: (context, t) => CustomPaint(
                    size: Size.square(size),
                    painter: _ArcGaugePainter(
                      progress: targetFraction * t,
                      strokeWidth: strokeWidth,
                      trackColor: HuxColors.chartTrack,
                      progressColor: accentColor,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    value == null
                        ? Text('—', style: numeralStyle)
                        : HuxCountUp(
                            value: value!,
                            format: format ?? (v) => v.round().toString(),
                            style: numeralStyle,
                          ),
                    if (unit != null && value != null) Text(unit!, style: textTheme.bodySmall),
                  ],
                ),
              ],
            ),
          ),
          if (labelPosition == HeroGaugeLabelPosition.below) ...[
            const SizedBox(height: HuxSpacing.sm),
            labelWidget,
          ],
        ],
      ),
    );
  }
}

/// A small hand-drawn downward-pointing triangle — the only non-
/// rectangular shape [SliderRangeCard] needs, so a `CustomPainter` is
/// used just for this rather than for the whole card.
class _TriangleMarkerPainter extends CustomPainter {
  final Color color;
  const _TriangleMarkerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TriangleMarkerPainter oldDelegate) => color != oldDelegate.color;
}

/// A horizontal range indicator: a pill track, an optional shaded
/// "normal range" band, a gradient fill up to [value]'s position, and a
/// small triangle marker at the fill's leading edge. Read-only — not a
/// draggable slider.
///
/// NULL: the fill and marker are omitted entirely (not drawn at
/// zero-width) — the track and normal-range band (a fixed reference)
/// still draw, and the header shows an em-dash instead of a value. This
/// is the one card in this file where null and a confirmed reading of
/// exactly [min] are NOT visually identical: a confirmed [min] still
/// draws a marker and a sliver of fill at the track's left edge.
class SliderRangeCard extends StatelessWidget {
  final String label;
  final double? value;
  final double min;
  final double max;
  final String? unit;
  final String Function(double)? format;
  final double? normalRangeMin;
  final double? normalRangeMax;
  final double trackHeight;
  final bool frosted;
  final Color tint;

  const SliderRangeCard({
    super.key,
    required this.label,
    required this.value,
    this.min = 0,
    this.max = 100,
    this.unit,
    this.format,
    this.normalRangeMin,
    this.normalRangeMax,
    this.trackHeight = 12,
    this.frosted = false,
    this.tint = HuxColors.accentPink,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final numeralStyle = textTheme.titleLarge?.copyWith(
      fontSize: HuxType.numeral,
      fontWeight: FontWeight.w700,
    );
    final range = max - min;
    final fraction = value == null ? null : ((value! - min) / range).clamp(0.0, 1.0);
    final bandStart = normalRangeMin == null ? null : ((normalRangeMin! - min) / range).clamp(0.0, 1.0);
    final bandEnd = normalRangeMax == null ? null : ((normalRangeMax! - min) / range).clamp(0.0, 1.0);
    final pillRadius = BorderRadius.circular(trackHeight / 2);

    return _SolidCardShell(
      frosted: frosted,
      tint: Color.alphaBlend(tint.withValues(alpha: 0.22), HuxColors.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: textTheme.bodySmall)),
              if (value == null)
                Text('—', style: numeralStyle)
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    HuxCountUp(
                      value: value!,
                      format: format ?? (v) => v.round().toString(),
                      style: numeralStyle,
                    ),
                    if (unit != null)
                      Padding(
                        padding: const EdgeInsets.only(left: HuxSpacing.xs, bottom: HuxSpacing.xs / 2),
                        child: Text(unit!, style: textTheme.bodySmall),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: HuxSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              return HuxChartGrowIn(
                builder: (context, t) {
                  final fillWidth = fraction == null ? 0.0 : (fraction * t * trackWidth).clamp(0.0, trackWidth);
                  return SizedBox(
                    height: trackHeight + 12,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            height: trackHeight,
                            decoration: BoxDecoration(color: HuxColors.chartTrack, borderRadius: pillRadius),
                          ),
                        ),
                        if (bandStart != null && bandEnd != null)
                          Positioned(
                            left: bandStart * trackWidth,
                            width: (bandEnd - bandStart) * trackWidth,
                            bottom: 0,
                            child: ClipRRect(
                              borderRadius: pillRadius,
                              child: Container(
                                height: trackHeight,
                                color: HuxColors.ink.withValues(alpha: HuxOpacity.targetBand),
                              ),
                            ),
                          ),
                        if (fraction != null) ...[
                          Positioned(
                            left: 0,
                            bottom: 0,
                            width: fillWidth,
                            child: ClipRRect(
                              borderRadius: pillRadius,
                              child: Container(
                                height: trackHeight,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(colors: [HuxColors.accentPink, HuxColors.accentCherry]),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: (fillWidth - 6).clamp(0.0, trackWidth - 12),
                            top: 0,
                            child: Opacity(
                              opacity: t,
                              child: const CustomPaint(
                                size: Size(12, 8),
                                painter: _TriangleMarkerPainter(color: HuxColors.ink),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Two arcs sharing one ring, back-to-back (not two concentric rings —
/// both sub-values here share one scale, so a single donut-with-colored-
/// slices communicates "how the whole split up" at a glance).
class _TwoSegmentArcPainter extends CustomPainter {
  final double primaryFraction;
  final double secondaryFraction;
  final double strokeWidth;
  final Color trackColor;
  final Color primaryColor;
  final Color secondaryColor;

  const _TwoSegmentArcPainter({
    required this.primaryFraction,
    required this.secondaryFraction,
    required this.strokeWidth,
    required this.trackColor,
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi, false, trackPaint);

    if (primaryFraction > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = primaryColor;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * primaryFraction, false, paint);
    }
    if (secondaryFraction > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = secondaryColor;
      canvas.drawArc(
        rect,
        -math.pi / 2 + 2 * math.pi * primaryFraction,
        2 * math.pi * secondaryFraction,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TwoSegmentArcPainter oldDelegate) =>
      primaryFraction != oldDelegate.primaryFraction ||
      secondaryFraction != oldDelegate.secondaryFraction ||
      strokeWidth != oldDelegate.strokeWidth ||
      trackColor != oldDelegate.trackColor ||
      primaryColor != oldDelegate.primaryColor ||
      secondaryColor != oldDelegate.secondaryColor;
}

/// A radial gauge split into two colored segments (e.g. last night's
/// deep vs REM sleep, against a shared total-sleep [max]) with a legend
/// row per sub-value below the ring.
///
/// [primaryValue]/[secondaryValue] are treated as a pair: both-null or
/// both-non-null, since a partial pair isn't a meaningful reading here.
/// NULL (both): the ring shows only the grey track (no segments drawn),
/// and both legend rows show an em-dash. Note a confirmed zero on one
/// sub-value draws the same zero-sweep segment null would — the legend
/// row's TEXT is the actual source of truth for the exact number in
/// either case, same role the numeral plays for [HeroGaugeCard].
class RadialProgressCard extends StatelessWidget {
  final String title;
  final double? primaryValue;
  final double? secondaryValue;
  final double max;
  final String primaryLabel;
  final String secondaryLabel;
  final Color primaryColor;
  final Color secondaryColor;
  final String Function(double)? format;
  final double size;
  final double strokeWidth;
  final bool frosted;

  const RadialProgressCard({
    super.key,
    required this.title,
    required this.primaryValue,
    required this.secondaryValue,
    required this.max,
    required this.primaryLabel,
    required this.secondaryLabel,
    this.primaryColor = HuxColors.accentPurple,
    this.secondaryColor = HuxColors.accentCherry,
    this.format,
    this.size = 140,
    this.strokeWidth = 14,
    this.frosted = false,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fmt = format ?? (v) => v.round().toString();
    final hasData = primaryValue != null && secondaryValue != null;
    final primaryFraction = hasData && max > 0 ? (primaryValue! / max).clamp(0.0, 1.0) : 0.0;
    final secondaryFraction =
        hasData && max > 0 ? (secondaryValue! / max).clamp(0.0, 1.0 - primaryFraction) : 0.0;

    return _SolidCardShell(
      frosted: frosted,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.bodySmall),
          const SizedBox(height: HuxSpacing.md),
          Center(
            child: SizedBox.square(
              dimension: size,
              child: HuxChartGrowIn(
                builder: (context, t) => CustomPaint(
                  size: Size.square(size),
                  painter: _TwoSegmentArcPainter(
                    primaryFraction: primaryFraction * t,
                    secondaryFraction: secondaryFraction * t,
                    strokeWidth: strokeWidth,
                    trackColor: HuxColors.chartTrack,
                    primaryColor: primaryColor,
                    secondaryColor: secondaryColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: HuxSpacing.md),
          _RadialLegendRow(color: primaryColor, label: primaryLabel, value: primaryValue, format: fmt),
          const SizedBox(height: HuxSpacing.xs),
          _RadialLegendRow(color: secondaryColor, label: secondaryLabel, value: secondaryValue, format: fmt),
        ],
      ),
    );
  }
}

class _RadialLegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final double? value;
  final String Function(double) format;

  const _RadialLegendRow({
    required this.color,
    required this.label,
    required this.value,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: HuxSpacing.xs),
        Text(label, style: textTheme.bodySmall),
        const Spacer(),
        Text(
          value == null ? '—' : format(value!),
          style: textTheme.bodySmall?.copyWith(color: HuxColors.ink, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// One bar in a [BarVisualizerCard].
class BarVisualizerDatum {
  final String label;
  final double? value;
  final Color color;

  const BarVisualizerDatum({required this.label, required this.value, this.color = HuxColors.accentCherry});
}

/// A hero numeral plus a row of vertical bars (an equalizer-style
/// glyph), one per [BarVisualizerDatum] — e.g. last night's sleep-stage
/// breakdown. Normalized against the TALLEST bar in the set (not an
/// external max), so at least one bar reaches full height — this
/// maximizes contrast between bars, the actual point of the glyph.
///
/// All bars share ONE grow-in factor (not staggered by index like
/// [HuxEntrance]) — they're one dataset, the direct analogue of a chart
/// line's whole-shape reveal, not independent entities arriving in
/// sequence.
///
/// NULL, per bar: a null value renders as a short, fixed, grey stub —
/// NEVER 0px, which would be visually identical to a confirmed-zero
/// reading (e.g. genuinely zero minutes awake). All-null renders every
/// bar as that stub plus an em-dash hero numeral.
class BarVisualizerCard extends StatelessWidget {
  final String title;
  final double? value;
  final String? unit;
  final String Function(double)? format;
  final List<BarVisualizerDatum> bars;
  final double maxBarHeight;
  final double barWidth;
  final bool frosted;
  final Color tint;

  static const _nullStubHeight = 6.0;

  const BarVisualizerCard({
    super.key,
    required this.title,
    required this.value,
    this.unit,
    this.format,
    required this.bars,
    this.maxBarHeight = 96,
    this.barWidth = 28,
    this.frosted = false,
    this.tint = HuxColors.accentCherry,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final numeralStyle = textTheme.titleLarge?.copyWith(
      fontSize: HuxType.numeral,
      fontWeight: FontWeight.w700,
    );
    final maxOfBars = bars.map((b) => b.value ?? 0).fold<double>(0, (a, b) => a > b ? a : b);

    return _SolidCardShell(
      frosted: frosted,
      tint: Color.alphaBlend(tint.withValues(alpha: 0.2), HuxColors.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.bodySmall),
          const SizedBox(height: HuxSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (value == null)
                Text('—', style: numeralStyle)
              else ...[
                HuxCountUp(value: value!, format: format ?? (v) => v.round().toString(), style: numeralStyle),
                if (unit != null)
                  Padding(
                    padding: const EdgeInsets.only(left: HuxSpacing.xs, bottom: HuxSpacing.xs / 2),
                    child: Text(unit!, style: textTheme.bodySmall),
                  ),
              ],
            ],
          ),
          const SizedBox(height: HuxSpacing.md),
          HuxChartGrowIn(
            builder: (context, t) => Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final bar in bars)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: maxBarHeight,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: Container(
                            width: barWidth,
                            height: bar.value == null || maxOfBars == 0
                                ? _nullStubHeight
                                : (bar.value! / maxOfBars) * maxBarHeight * t,
                            decoration: BoxDecoration(
                              color: bar.value == null
                                  ? HuxColors.mutedText.withValues(alpha: 0.4)
                                  : bar.color,
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: HuxSpacing.xs),
                      Text(bar.label, style: textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A bottom-sheet nudge: glowing icon, title, message, and two pill
/// buttons — wired to a REAL async action via [onPrimary], not a purely
/// decorative dialog. The primary button disables itself and shows a
/// spinner while [onPrimary] is in flight, pops the sheet on success,
/// and shows inline error text (never a silent dismiss) on failure so
/// the user can retry without reopening it.
class NudgeModal extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color accentColor;
  final String primaryLabel;
  final Future<void> Function() onPrimary;
  final String secondaryLabel;

  const NudgeModal({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.accentColor = HuxColors.accentPink,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel = 'Dismiss',
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    Color accentColor = HuxColors.accentPink,
    required String primaryLabel,
    required Future<void> Function() onPrimary,
    String secondaryLabel = 'Dismiss',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => NudgeModal(
        title: title,
        message: message,
        icon: icon,
        accentColor: accentColor,
        primaryLabel: primaryLabel,
        onPrimary: onPrimary,
        secondaryLabel: secondaryLabel,
      ),
    );
  }

  @override
  State<NudgeModal> createState() => _NudgeModalState();
}

class _NudgeModalState extends State<NudgeModal> {
  bool _sending = false;
  String? _error;

  /// Strips a raw exception's `SomeException: ` prefix, same convention
  /// as today_screen.dart's `_ErrorView._friendly`.
  static String _friendly(String raw) => raw.replaceFirst(RegExp(r'^\w*Exception:\s*'), '');

  Future<void> _handlePrimary() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onPrimary();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = _friendly(e.toString());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(HuxSpacing.lg),
        child: _SolidCardShell(
          frosted: true,
          tint: Color.alphaBlend(widget.accentColor.withValues(alpha: 0.14), HuxColors.cardElevated),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.accentColor.withValues(alpha: HuxOpacity.iconChip),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: HuxOpacity.panelGlow),
                      blurRadius: HuxGlass.glowBlurRadius,
                      spreadRadius: HuxGlass.glowSpread,
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: widget.accentColor, size: 32),
              ),
              const SizedBox(height: HuxSpacing.lg),
              Text(widget.title, style: textTheme.displaySmall, textAlign: TextAlign.center),
              const SizedBox(height: HuxSpacing.sm),
              Text(widget.message, style: textTheme.bodyMedium, textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: HuxSpacing.sm),
                Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(color: HuxColors.rundown),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: HuxSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _sending ? null : () => Navigator.of(context).pop(),
                      child: Text(widget.secondaryLabel),
                    ),
                  ),
                  const SizedBox(width: HuxSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _sending ? null : _handlePrimary,
                      style: FilledButton.styleFrom(
                        backgroundColor: widget.accentColor,
                        foregroundColor: HuxColors.inkOnAccent,
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.primaryLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
