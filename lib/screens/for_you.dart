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

  Future<void> _edit() async {
    await widget.onEditAnswers();
    if (mounted) {
      setState(() {
        _featured = widget.profileService.featured();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: [
          TextButton(onPressed: _edit, child: const Text('Edit my answers')),
        ],
      ),
      body: FutureBuilder<List<FeatureId>>(
        future: _featured,
        builder: (context, snapshot) {
          final featured = (snapshot.data ?? const <FeatureId>[]).where(isFeatureVisible).toList();
          return ListView(
            padding: const EdgeInsets.all(HuxSpacing.lg),
            children: [
              if (featured.isNotEmpty) ...[
                Text('Recommended for you', style: text.titleMedium),
                const SizedBox(height: HuxSpacing.sm),
                for (final id in featured) ...[
                  FeatureCard(info: FeatureCatalog.of(id), onTap: () => widget.onOpen(id)),
                  const SizedBox(height: HuxSpacing.sm),
                ],
                const SizedBox(height: HuxSpacing.lg),
              ],
              for (final category in FeatureCategory.values) ...[
                Text(category.label, style: text.titleMedium),
                const SizedBox(height: HuxSpacing.sm),
                for (final info in FeatureCatalog.all
                    .where((f) => f.category == category && isFeatureVisible(f.id))) ...[
                  FeatureCard(info: info, onTap: () => widget.onOpen(info.id)),
                  const SizedBox(height: HuxSpacing.sm),
                ],
                const SizedBox(height: HuxSpacing.lg),
              ],
            ],
          );
        },
      ),
    );
  }
}
