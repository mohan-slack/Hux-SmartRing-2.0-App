/// HUX light UI kit (OxeAI-inspired): score rings, ask bar, agenda rows,
/// stat grids, section headers, avatar and the floating pill nav bar.
/// Everything reads colours from hux_tokens.dart.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hux_motion.dart';
import 'hux_tokens.dart';

// ---------------------------------------------------------------------------
// Score ring
// ---------------------------------------------------------------------------

/// A round progress ring with the value in the middle. [progress] 0..1;
/// null shows an empty track and "—" (never a fake number).
class HuxScoreRing extends StatelessWidget {
  final double? progress;
  final String centerText;
  final Color color;
  final double size;
  final double stroke;
  final TextStyle? centerStyle;

  const HuxScoreRing({
    super.key,
    required this.progress,
    required this.centerText,
    required this.color,
    this.size = 64,
    this.stroke = 7,
    this.centerStyle,
  });

  @override
  Widget build(BuildContext context) {
    final style = centerStyle ??
        Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final label = Center(
      child: Padding(
        padding: EdgeInsets.all(stroke + 2),
        child: FittedBox(child: Text(centerText, style: style)),
      ),
    );
    return SizedBox(
      width: size,
      height: size,
      // The arc sweeps in from its last value (from empty on first
      // build) — finite, so it never blocks pumpAndSettle.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: (progress ?? 0).clamp(0.0, 1.0)),
        duration: HuxMotion.slow,
        curve: HuxMotion.easeOut,
        builder: (context, v, child) => CustomPaint(
          painter: _RingPainter(progress: progress == null ? null : v, color: color, stroke: stroke),
          child: child,
        ),
        child: label,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double? progress;
  final Color color;
  final double stroke;

  _RingPainter({required this.progress, required this.color, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withValues(alpha: 0.14);
    canvas.drawArc(r, 0, math.pi * 2, false, track);
    final p = progress;
    if (p == null || p <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * p.clamp(0.0, 1.0), false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color || old.stroke != stroke;
}

/// Ring + label underneath, used three-across on Home.
class HuxRingTile extends StatelessWidget {
  final String label;
  final String value;
  final String? caption;
  final double? progress;
  final Color color;
  final VoidCallback? onTap;

  const HuxRingTile({
    super.key,
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
    this.caption,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      label: '$label $value${caption == null ? '' : ', $caption'}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HuxRadii.card),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HuxSpacing.sm),
          child: Column(
            children: [
              HuxScoreRing(progress: progress, centerText: value, color: color, size: 68),
              const SizedBox(height: HuxSpacing.sm),
              Text(label, style: text.labelLarge, textAlign: TextAlign.center),
              if (caption != null)
                Text(caption!,
                    style: text.labelSmall,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ask bar, section title, icon badge, avatar
// ---------------------------------------------------------------------------

/// "Ask HUX anything…" pill with a gradient outline (OxeAI's ask box).
class HuxAskBar extends StatelessWidget {
  final String hint;
  final VoidCallback onTap;

  const HuxAskBar({super.key, this.hint = 'Ask HUX anything…', required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(HuxRadii.chip),
            gradient: const LinearGradient(colors: [HuxColors.ringSleep, HuxColors.ringCharge, HuxColors.ringSteps]),
          ),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.lg),
            decoration: BoxDecoration(
              color: HuxColors.card,
              borderRadius: BorderRadius.circular(HuxRadii.chip),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18, color: HuxColors.ringCharge),
                const SizedBox(width: HuxSpacing.sm),
                Expanded(
                  child: Text(hint,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: HuxColors.mutedText)),
                ),
                const Icon(Icons.arrow_upward_rounded, size: 18, color: HuxColors.mutedText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase section label with an optional action on the right.
class HuxSectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color? iconColor;
  final String? actionLabel;
  final VoidCallback? onAction;

  const HuxSectionTitle(this.title, {super.key, this.icon, this.iconColor, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: HuxSpacing.sm),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: iconColor ?? HuxColors.accentPink),
            const SizedBox(width: HuxSpacing.xs),
          ],
          Expanded(
            child: Text(title.toUpperCase(),
                style: text.labelLarge?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: EdgeInsets.zero),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// A rounded square with a coloured icon (agenda rows, plan cards).
class HuxIconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;

  const HuxIconBadge({super.key, required this.icon, required this.color, this.size = 40});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// Round avatar with the user's initial (top-left of Home).
class HuxAvatar extends StatelessWidget {
  final String initial;
  final VoidCallback? onTap;

  const HuxAvatar({super.key, required this.initial, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Profile and settings',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: HuxColors.card,
            border: Border.all(color: HuxColors.glassStroke),
            boxShadow: const [BoxShadow(color: HuxColors.shadow, blurRadius: 10, offset: Offset(0, 3))],
          ),
          child: Text(initial,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: HuxColors.accentPurple,
                    fontWeight: FontWeight.w700,
                  )),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Agenda + stats
// ---------------------------------------------------------------------------

/// One timeline row: time on the left, coloured badge, title + detail.
class HuxAgendaItem extends StatelessWidget {
  final String time;
  final IconData icon;
  final Color color;
  final String title;
  final String? detail;
  final bool done;

  /// Earlier today and not done: shown faded.
  final bool past;
  final VoidCallback? onTap;

  const HuxAgendaItem({
    super.key,
    required this.time,
    required this.icon,
    required this.color,
    required this.title,
    this.detail,
    this.done = false,
    this.past = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final item = Material(
      type: MaterialType.transparency,
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(HuxSpacing.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HuxSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 58,
              child: Padding(
                padding: const EdgeInsets.only(top: HuxSpacing.sm),
                child: Text(time, style: text.labelMedium),
              ),
            ),
            HuxIconBadge(icon: done ? Icons.check_rounded : icon, color: done ? HuxColors.recharged : color),
            const SizedBox(width: HuxSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? HuxColors.mutedText : HuxColors.ink,
                      )),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(detail!, style: text.bodySmall),
                  ],
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: HuxColors.mutedText, size: 20),
          ],
        ),
      ),
      ),
    );
    return past && !done ? Opacity(opacity: 0.55, child: item) : item;
  }
}

class HuxStat {
  final String label;
  final String value;
  final String? unit;
  const HuxStat(this.label, this.value, {this.unit});
}

/// A two-column grid of small labelled numbers (OxeAI's sleep card).
class HuxStatGrid extends StatelessWidget {
  final List<HuxStat> stats;

  const HuxStatGrid({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rows = <Widget>[];
    for (var i = 0; i < stats.length; i += 2) {
      Widget cell(HuxStat s) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: HuxSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.label, style: text.labelMedium),
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(children: [
                    TextSpan(text: s.value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    if (s.unit != null) TextSpan(text: ' ${s.unit}', style: text.labelSmall),
                  ])),
                ],
              ),
            ),
          );
      rows.add(Row(children: [cell(stats[i]), if (i + 1 < stats.length) cell(stats[i + 1]) else const Spacer()]));
      if (i + 2 < stats.length) rows.add(const Divider(height: 1, color: HuxColors.hairline));
    }
    return Column(children: rows);
  }
}

// ---------------------------------------------------------------------------
// Floating pill navigation bar + "+" button
// ---------------------------------------------------------------------------

class HuxNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const HuxNavItem(this.icon, this.selectedIcon, this.label);
}

/// OxeAI-style floating bar: a white pill with icon tabs, plus a round
/// accent "+" button on the right for quick logging.
class HuxPillNavBar extends StatelessWidget {
  final List<HuxNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback? onPlus;

  const HuxPillNavBar({super.key, required this.items, required this.index, required this.onSelect, this.onPlus});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // The bar has a fixed height: cap text scaling inside it so large
    // accessibility text never overflows the tabs (content screens
    // still scale fully).
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: HuxSpacing.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.lg),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.xs),
                decoration: BoxDecoration(
                  color: HuxColors.card,
                  borderRadius: BorderRadius.circular(HuxRadii.chip),
                  border: Border.all(color: HuxColors.glassStroke),
                  boxShadow: const [BoxShadow(color: HuxColors.shadow, blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(
                        child: Semantics(
                          selected: i == index,
                          button: true,
                          label: items[i].label,
                          excludeSemantics: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(HuxRadii.chip),
                            onTap: () {
                              if (i != index) HapticFeedback.selectionClick();
                              onSelect(i);
                            },
                            child: AnimatedContainer(
                              duration: HuxMotion.quick,
                              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                              decoration: BoxDecoration(
                                color: i == index ? HuxColors.cardElevated : Colors.transparent,
                                borderRadius: BorderRadius.circular(HuxRadii.chip),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedScale(
                                    scale: i == index ? 1.12 : 1,
                                    duration: HuxMotion.quick,
                                    curve: HuxMotion.easeOut,
                                    child: Icon(i == index ? items[i].selectedIcon : items[i].icon,
                                        size: 22, color: i == index ? HuxColors.accentPurple : HuxColors.mutedText),
                                  ),
                                  Text(items[i].label,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: text.labelSmall?.copyWith(
                                        color: i == index ? HuxColors.accentPurple : HuxColors.mutedText,
                                        fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                                      )),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (onPlus != null) ...[
              const SizedBox(width: HuxSpacing.sm),
              Semantics(
                button: true,
                label: 'Quick log',
                excludeSemantics: true,
                child: HuxTapScale(
                  child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onPlus!();
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [HuxColors.ringCharge, HuxColors.accentPurple],
                      ),
                      boxShadow: [BoxShadow(color: HuxColors.shadow, blurRadius: 16, offset: Offset(0, 6))],
                    ),
                    child: const Icon(Icons.add_rounded, color: HuxColors.onVivid, size: 30),
                  ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mini bar trend (7 days)
// ---------------------------------------------------------------------------

/// Seven small rounded bars; the last one highlighted. Nulls show as a
/// faint stub (no data), never as zero.
class HuxMiniBars extends StatelessWidget {
  final List<double?> values;
  final Color color;
  final double height;

  const HuxMiniBars({super.key, required this.values, required this.color, this.height = 44});

  @override
  Widget build(BuildContext context) {
    final present = values.whereType<double>();
    final max = present.isEmpty ? 1.0 : present.reduce(math.max);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: values[i] == null || max <= 0 ? 0.06 : (values[i]! / max).clamp(0.06, 1.0)),
                  duration: HuxMotion.slow,
                  curve: HuxMotion.easeOut,
                  builder: (_, f, __) => Container(
                    height: height * f,
                    decoration: BoxDecoration(
                      color: values[i] == null
                          ? HuxColors.hairline
                          : (i == values.length - 1 ? color : color.withValues(alpha: 0.35)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
