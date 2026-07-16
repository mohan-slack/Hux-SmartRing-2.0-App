/// Story screen — the Weekly Body Story, rendered as plain readable
/// paragraphs. Deliberately undesigned; a later design phase restyles
/// this. Keep widgets small and composable so that pass is cheap.
///
/// Talks only to [WeeklyStoryService].

import 'package:flutter/material.dart';

import '../core/meaning/weekly_story.dart';

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
          const SizedBox(height: 16),
          Text(message),
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
      padding: const EdgeInsets.all(16),
      children: [
        Text(story.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        _Observations(observations: story.observations),
        const Divider(height: 32),
        _Suggestion(suggestion: story.suggestion),
      ],
    );
  }
}

class _Observations extends StatelessWidget {
  final List<String> observations;

  const _Observations({required this.observations});

  @override
  Widget build(BuildContext context) {
    if (observations.isEmpty) {
      return const Text("Nothing to compare yet — check back once you've "
          'logged a bit more.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final observation in observations)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(observation,
                style: Theme.of(context).textTheme.bodyLarge),
          ),
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  final String suggestion;

  const _Suggestion({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('For next week', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Text(suggestion),
      ],
    );
  }
}
