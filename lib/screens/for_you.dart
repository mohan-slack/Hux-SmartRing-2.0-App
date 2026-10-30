/// "For you" — the personalised part of the app.
///
/// - [ForYouSection]: the 2–4 featured cards on Today.
/// - [ExploreScreen]: every feature, recommended ones first, plus
///   "Edit my answers".
/// - [showComingSoonSheet]: honest "not built yet — want it sooner?"
///   for planned features, never a fake screen.
library;

import 'package:flutter/material.dart';

import '../core/profile/feature_catalog.dart';
import '../core/profile/profile_service.dart';
import '../theme/hux_glass.dart';
import '../theme/hux_tokens.dart';
import '../widgets/hux/hux_3d.dart';
import '../widgets/hux/hux_kit.dart';

typedef FeatureTap = void Function(FeatureId id);

class ForYouSection extends StatelessWidget {
  final List<FeatureId> featured;
  final FeatureTap onOpen;
  final VoidCallback onSeeAll;

  const ForYouSection({
    super.key,
    required this.featured,
    required this.onOpen,
    required this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('For you', style: text.titleMedium)),
            TextButton(onPressed: onSeeAll, child: const Text('See all')),
          ],
        ),
        const SizedBox(height: HuxSpacing.sm),
        for (final id in featured.where(isFeatureVisible)) ...[
          FeatureCard(info: FeatureCatalog.of(id), onTap: () => onOpen(id)),
          const SizedBox(height: HuxSpacing.sm),
        ],
      ],
    );
  }
}

class FeatureCard extends StatelessWidget {
  final FeatureInfo info;
  final VoidCallback onTap;

  const FeatureCard({super.key, required this.info, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '${info.title}. ${info.blurb}${info.isAvailable ? '' : ' Coming soon.'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: GlassPanel(
          padding: const EdgeInsets.all(HuxSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.title, style: text.titleSmall),
                    const SizedBox(height: HuxSpacing.xs),
                    Text(
                      info.blurb,
                      style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: HuxSpacing.sm),
              if (!info.isAvailable)
                const _Badge(label: 'Coming soon')
              else
                const Icon(Icons.chevron_right, color: HuxColors.mutedText),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  const _Badge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.sm, vertical: HuxSpacing.xs),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HuxRadii.chip),
        border: Border.all(color: HuxColors.glassStroke),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: HuxColors.mutedText),
      ),
    );
  }
}

/// Planned feature tapped: say so plainly, and let the user vote.
Future<void> showComingSoonSheet(
  BuildContext context, {
  required FeatureInfo info,
  required bool alreadyVoted,
  required Future<void> Function() onVote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final text = Theme.of(sheetContext).textTheme;
      var voted = alreadyVoted;
      return StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(HuxSpacing.xl, 0, HuxSpacing.xl, HuxSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(info.title, style: text.titleLarge),
              const SizedBox(height: HuxSpacing.sm),
              Text(info.blurb, style: text.bodyMedium),
              const SizedBox(height: HuxSpacing.md),
              Text(
                "We're building this. Tell us you want it and we'll prioritise it.",
                style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
              ),
              const SizedBox(height: HuxSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: voted
                      ? null
                      : () async {
                          await onVote();
                          setSheetState(() => voted = true);
                        },
                  child: Text(voted ? 'Thanks — noted' : 'I want this'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class ExploreScreen extends StatefulWidget {
  final ProfileService profileService;
  final FeatureTap onOpen;
  final Future<void> Function() onEditAnswers;

  const ExploreScreen({
    super.key,
    required this.profileService,
    required this.onOpen,
    required this.onEditAnswers,
  });

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  late Future<List<FeatureId>> _featured = widget.profileService.featured();

  /// null = "For you"; otherwise one category. "All" is [_all].
  FeatureCategory? _category;
  bool _all = false;

  Future<void> _edit() async {
    await widget.onEditAnswers();
    if (mounted) {
      setState(() {
        _featured = widget.profileService.featured();
      });
    }
  }

  static Color colorOf(FeatureCategory c) => switch (c) {
        FeatureCategory.recovery => HuxColors.ringCharge,
        FeatureCategory.sleep => HuxColors.ringSleep,
        FeatureCategory.activity => HuxColors.ringSteps,
        FeatureCategory.food => HuxColors.ringFood,
        FeatureCategory.mind => const Color(0xFFB08800),
        FeatureCategory.family => HuxColors.accentIndigo,
        FeatureCategory.modes => HuxColors.accentPurple,
      };

  Widget _grid(List<FeatureInfo> items) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: 10));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _FeatureTile(info: items[i], color: colorOf(items[i].category), onTap: () => widget.onOpen(items[i].id))),
            const SizedBox(width: 10),
            Expanded(
              child: i + 1 < items.length
                  ? _FeatureTile(
                      info: items[i + 1], color: colorOf(items[i + 1].category), onTap: () => widget.onOpen(items[i + 1].id))
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All features'),
        actions: [TextButton(onPressed: _edit, child: const Text('Edit answers'))],
      ),
      body: FutureBuilder<List<FeatureId>>(
        future: _featured,
        builder: (context, snapshot) {
          final featured = (snapshot.data ?? const <FeatureId>[]).where(isFeatureVisible).toList();
          final showForYou = !_all && _category == null && featured.isNotEmpty;
          List<FeatureInfo> inCategory(FeatureCategory c) =>
              FeatureCatalog.all.where((f) => f.category == c && isFeatureVisible(f.id)).toList();

          Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => onTap(),
                  showCheckmark: false,
                  shape: const StadiumBorder(),
                  side: BorderSide.none,
                  backgroundColor: Colors.white,
                  selectedColor: huxInk,
                  labelStyle: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: selected ? Colors.white : huxInk),
                ),
              );

          final cats = [for (final c in FeatureCategory.values) if (inCategory(c).isNotEmpty) c];
          return ListView(
            padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, 4, HuxSpacing.lg, HuxSpacing.xl),
            children: [
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (featured.isNotEmpty)
                      chip('For you', showForYou, () => setState(() {
                            _all = false;
                            _category = null;
                          })),
                    chip('All', _all || (featured.isEmpty && _category == null), () => setState(() {
                          _all = true;
                          _category = null;
                        })),
                    for (final c in cats)
                      chip(c.label, !_all && _category == c, () => setState(() {
                            _all = false;
                            _category = c;
                          })),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (showForYou)
                _grid([for (final id in featured) FeatureCatalog.of(id)])
              else if (_category != null)
                _grid(inCategory(_category!))
              else
                for (final c in cats) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 10),
                    child: Text(c.label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: huxInk)),
                  ),
                  _grid(inCategory(c)),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }
}

/// One feature: its floating 3D object on a soft tint, the name, and
/// "Soon" when not built yet.
class _FeatureTile extends StatelessWidget {
  final FeatureInfo info;
  final Color color;
  final VoidCallback onTap;

  const _FeatureTile({required this.info, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final on = info.isAvailable;
    return Semantics(
      button: true,
      label: '${info.title}. ${info.blurb}${on ? '' : ' Coming soon.'}',
      excludeSemantics: true,
      child: Material(
        color: Color.alphaBlend(color.withValues(alpha: on ? 0.13 : 0.06), Colors.white),
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: on ? 1 : 0.55,
                      child: Hux3DObject(hux3dFor(info.id), color: color, size: 62),
                    ),
                    const Spacer(),
                    if (!on)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                        child: const Text('Soon', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: huxMuted)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(info.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800, height: 1.25, color: on ? huxInk : huxMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
