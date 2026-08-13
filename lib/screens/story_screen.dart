/// Story screen — the Weekly Body Story, rendered as plain readable
/// paragraphs. Deliberately undesigned; a later design phase restyles
/// this. Keep widgets small and composable so that pass is cheap.
///
/// Talks only to [WeeklyStoryService].

import 'package:flutter/material.dart';

import '../core/meaning/weekly_story.dart';
import '../theme/hux_glass.dart';
import '../theme/hux_motion.dart';
import '../theme/hux_tokens.dart';

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
      // Bottom clearance: content scrolls behind the glass nav bar.
      padding: const EdgeInsets.fromLTRB(
          HuxSpacing.lg, HuxSpacing.lg, HuxSpacing.lg, HuxGlass.navClearance),
      children: [
        HuxEntrance(
          child: Text(story.title,
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 1,
          child: _Observations(observations: story.observations),
        ),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 2,
          child: _Suggestion(suggestion: story.suggestion),
        ),
      ],
    );
  }
}

class _Observations extends StatelessWidget {
  final List<String> observations;

  const _Observations({required this.observations});

  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyLarge;
    if (observations.isEmpty) {
      return Text(
        "Nothing to compare yet — check back once you've logged a bit "
        'more.',
        style: bodyStyle,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final observation in observations)
          Padding(
            padding: const EdgeInsets.only(bottom: HuxSpacing.md),
            child: Text(observation, style: bodyStyle),
          ),
      ],
    );
  }
}

/// "For next week" — a distinct glowing glass card, not just another
/// paragraph: this is the one concrete thing to act on, so it reads
/// as the lit-up takeaway at the end of the story.
class _Suggestion extends StatelessWidget {
  final String suggestion;

  const _Suggestion({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return GlassPanel(
      frosted: true,
      tint: HuxColors.accentPink.withValues(alpha: HuxOpacity.activeCardWash),
      glow: HuxColors.accentPink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('For next week',
              style: textTheme.labelLarge
                  ?.copyWith(color: HuxModeAccent.background)),
          const SizedBox(height: HuxSpacing.sm),
          Text(suggestion, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}
