/// Story screen — the Weekly Body Story, rendered as plain readable
/// paragraphs. Deliberately undesigned; a later design phase restyles
/// this. Keep widgets small and composable so that pass is cheap.
///
/// Talks only to [WeeklyStoryService].

import 'package:flutter/material.dart';

import '../core/meaning/weekly_story.dart';
import '../theme/hux_motion.dart';
import '../theme/hux_page.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';
import '../widgets/wellness_note.dart';

class StoryScreen extends StatefulWidget {
  final WeeklyStoryService storyService;

  const StoryScreen({super.key, required this.storyService});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  late Future<WeeklyStory> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.storyService.buildStory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Transparent: this screen lives inside AppShell's IndexedStack,
      // over the ONE shared HuxBackground — it must not paint its own.
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: FutureBuilder<WeeklyStory>(
          future: _future,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const _MessageView(message: 'Building your week…');
            }
            return _StoryBody(story: snapshot.data!);
          },
        ),
      ),
    );
  }
}

class _MessageView extends StatelessWidget {
  final String message;

  const _MessageView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: HuxSpacing.lg),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _StoryBody extends StatelessWidget {
  final WeeklyStory story;

  const _StoryBody({required this.story});

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Bottom clearance: content scrolls behind the floating nav bar.
      padding: const EdgeInsets.fromLTRB(
          HuxSpacing.lg, HuxSpacing.lg, HuxSpacing.lg, HuxGlass.navClearance),
      children: [
        HuxEntrance(
          child: HuxHeroCard(
            icon: Icons.auto_stories_rounded,
            color: HuxColors.accentPurple,
            eyebrow: 'Your week',
            title: story.title,
          ),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 1,
          child: _Observations(observations: story.observations),
        ),
        const SizedBox(height: HuxSpacing.md),
        HuxEntrance(
          index: 2,
          child: _Suggestion(suggestion: story.suggestion),
        ),
        const WellnessNote(),
      ],
    );
  }
}

class _Observations extends StatelessWidget {
  final List<String> observations;

  const _Observations({required this.observations});

  static const _colors = [HuxColors.ringSleep, HuxColors.ringCharge, HuxColors.ringSteps, HuxColors.ringFood];

  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    if (observations.isEmpty) {
      return const HuxEmptyState(
        icon: Icons.hourglass_empty_rounded,
        color: HuxColors.accentPurple,
        title: "Nothing to compare yet — check back once you've logged a bit more.",
      );
    }
    return HuxCard(
      padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
      child: Column(
        children: [
          for (var i = 0; i < observations.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: HuxColors.hairline),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HuxSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HuxIconBadge(icon: Icons.insights_rounded, color: _colors[i % _colors.length], size: 36),
                  const SizedBox(width: HuxSpacing.md),
                  Expanded(child: Text(observations[i], style: bodyStyle)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "For next week" — the one concrete thing to act on, so it gets the
/// tinted hero treatment rather than reading as another paragraph.
class _Suggestion extends StatelessWidget {
  final String suggestion;

  const _Suggestion({required this.suggestion});

  @override
  Widget build(BuildContext context) => HuxHeroCard(
        icon: Icons.lightbulb_rounded,
        color: HuxColors.accentPink,
        eyebrow: 'For next week',
        title: suggestion,
      );
}
