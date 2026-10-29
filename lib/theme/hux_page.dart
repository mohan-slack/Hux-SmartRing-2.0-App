/// HUX light page kit — the building blocks every secondary screen
/// (Food, Journal, Plans, Privacy, Modes…) is assembled from, so they
/// all read like Home: a tinted hero card on top, white cards below,
/// coloured icon badges, rounded progress bars.
/// Colours come from hux_tokens.dart only.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'hux_motion.dart';
import 'hux_tokens.dart';
import 'hux_ui.dart';

/// Tinted hero card at the top of a screen: icon badge, small eyebrow,
/// big title/value, subtitle, optional trailing action and extra child.
class HuxHeroCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;

  const HuxHeroCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.trailing,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return HuxEntrance(
      child: Container(
      padding: const EdgeInsets.all(HuxSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HuxRadii.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(color.withValues(alpha: 0.16), HuxColors.card), HuxColors.card],
        ),
        border: Border.all(color: color.withValues(alpha: 0.18)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HuxIconBadge(icon: icon, color: color, size: 44),
              const SizedBox(width: HuxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null)
                      Text(eyebrow!.toUpperCase(),
                          style: text.labelSmall?.copyWith(
                              color: color, letterSpacing: 0.8, fontWeight: FontWeight.w700)),
                    Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: HuxSpacing.md),
            child!,
          ],
        ],
      ),
      ),
    );
  }
}

/// Plain white card (the standard surface below the hero).
class HuxCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const HuxCard({super.key, required this.child, this.padding = const EdgeInsets.all(HuxSpacing.lg), this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(HuxRadii.card);
    final card = Container(
      decoration: BoxDecoration(
        color: HuxColors.card,
        borderRadius: radius,
        border: Border.all(color: HuxColors.glassStroke),
        boxShadow: const [BoxShadow(color: HuxColors.shadow, blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap == null
              ? null
              : () {
                  HapticFeedback.selectionClick();
                  onTap!();
                },
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
    // Tappable cards dip slightly under the finger.
    return onTap == null ? card : HuxTapScale(child: card);
  }
}

/// Rounded progress bar. [value] 0..1 (clamped).
class HuxProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const HuxProgressBar({super.key, required this.value, required this.color, this.height = 8});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(HuxRadii.chip),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0),
          minHeight: height,
          color: color,
          backgroundColor: color.withValues(alpha: 0.14),
        ),
      );
}

/// Square-ish action tile: coloured badge over a short label.
class HuxActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const HuxActionTile({super.key, required this.icon, required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: HuxCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(vertical: HuxSpacing.lg, horizontal: HuxSpacing.sm),
          child: Column(
            children: [
              HuxIconBadge(icon: icon, color: color, size: 44),
              const SizedBox(height: HuxSpacing.sm),
              Text(label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

/// A list row inside a card: badge, title, subtitle, trailing widget.
class HuxListRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const HuxListRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(HuxSpacing.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HuxSpacing.sm),
          child: Row(
            children: [
              HuxIconBadge(icon: icon, color: color),
              const SizedBox(width: HuxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                const Icon(Icons.chevron_right, color: HuxColors.mutedText, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small coloured chip: "Carbs 120 g".
class HuxPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const HuxPill({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(HuxRadii.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: color),
              const SizedBox(width: HuxSpacing.xs),
            ],
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// Friendly empty state: badge, title, one line of help.
class HuxEmptyState extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? body;

  const HuxEmptyState({super.key, required this.icon, required this.color, required this.title, this.body});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return HuxCard(
      child: Column(
        children: [
          HuxIconBadge(icon: icon, color: color, size: 52),
          const SizedBox(height: HuxSpacing.md),
          Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          if (body != null) ...[
            const SizedBox(height: HuxSpacing.xs),
            Text(body!, style: text.bodySmall?.copyWith(color: HuxColors.mutedText), textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

/// Full-screen "working on it" veil (light, not a black flood).
class HuxBusyOverlay extends StatelessWidget {
  final String message;

  const HuxBusyOverlay({super.key, required this.message});

  @override
  Widget build(BuildContext context) => Positioned.fill(
        child: ColoredBox(
          color: HuxColors.bg.withValues(alpha: 0.85),
          child: Center(
            child: HuxCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
                  const SizedBox(height: HuxSpacing.md),
                  Text(message, style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
            ),
          ),
        ),
      );
}
