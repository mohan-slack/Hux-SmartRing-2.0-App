/// Progress tab: Trends, weekly Story and Streaks behind one segmented
/// switch. [section] lets other parts of the app open a given section.
library;

import 'package:flutter/material.dart';

import '../../core/meaning/weekly_story.dart';
import '../../core/progress/progress_service.dart';
import '../../core/storage/health_store.dart';
import '../../theme/hux_tokens.dart';
import '../progress/progress_screen.dart';
import '../story_screen.dart';
import '../trends_screen.dart';

enum ProgressSection { trends, story, streaks }

class ProgressHub extends StatelessWidget {
  final HealthStore store;
  final WeeklyStoryService storyService;
  final ProgressService progress;
  final ValueNotifier<ProgressSection> section;

  const ProgressHub({
    super.key,
    required this.store,
    required this.storyService,
    required this.progress,
    required this.section,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ValueListenableBuilder<ProgressSection>(
      valueListenable: section,
      builder: (context, current, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Progress', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: HuxSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ProgressSection>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: ProgressSection.trends, label: Text('Trends')),
                      ButtonSegment(value: ProgressSection.story, label: Text('Story')),
                      ButtonSegment(value: ProgressSection.streaks, label: Text('Streaks')),
                    ],
                    selected: {current},
                    onSelectionChanged: (s) => section.value = s.first,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: current.index,
              children: [
                TrendsScreen(store: store),
                StoryScreen(storyService: storyService),
                ProgressScreen(progress: progress, embedded: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
