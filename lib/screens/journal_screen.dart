/// Daily journal: one-tap tags for today (or yesterday), saved on tap,
/// and — once there's enough data — the user's own patterns below.
library;

import 'package:flutter/material.dart';

import '../core/journal/journal.dart';
import '../theme/hux_page.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';

class JournalScreen extends StatefulWidget {
  final JournalService journal;

  const JournalScreen({super.key, required this.journal});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  /// 0 = today, 1 = yesterday (habits are often logged next morning).
  int _daysAgo = 0;
  Set<JournalTag> _tags = {};
  List<JournalInsight> _insights = const [];
  int _loggedDays = 0;
  bool _loading = true;
  String? _error;

  DateTime get _day => DateTime.now().subtract(Duration(days: _daysAgo));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tags = await widget.journal.tagsFor(_day);
      final insights = await widget.journal.insights();
      final logged = await widget.journal.loggedDays();
      if (!mounted) return;
      setState(() {
        _tags = {...tags};
        _insights = insights;
        _loggedDays = logged;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load your journal. Please try again.";
      });
    }
  }

  Future<void> _toggle(JournalTag tag) async {
    final next = {..._tags};
    if (!next.remove(tag)) next.add(tag);
    setState(() => _tags = next); // optimistic: chips respond instantly
    try {
      await widget.journal.setTags(_day, next);
      final logged = await widget.journal.loggedDays();
      if (mounted) setState(() => _loggedDays = logged);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (!_tags.remove(tag)) _tags.add(tag);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't save — try again.")),
      );
    }
  }

  static const _groups = <(String, IconData, Color, List<JournalTag>)>[
    ('Food & drink', Icons.local_cafe_outlined, HuxColors.ringSteps, [
      JournalTag.chai3plus,
      JournalTag.coffeeLate,
      JournalTag.lateDinner,
      JournalTag.heavyMeal,
      JournalTag.sweets,
      JournalTag.alcohol,
    ]),
    ('Movement', Icons.directions_walk_rounded, HuxColors.ringFood, [
      JournalTag.workout,
      JournalTag.yoga,
      JournalTag.walkAfterMeal,
    ]),
    ('Your day', Icons.wb_twilight_rounded, HuxColors.ringSleep, [
      JournalTag.screenInBed,
      JournalTag.dayNap,
      JournalTag.travel,
      JournalTag.stressfulDay,
      JournalTag.festival,
      JournalTag.unwell,
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Any tag not placed in a group still shows (future-proof).
    final grouped = {for (final g in _groups) ...g.$4};
    final groups = [
      ..._groups,
      if (JournalTag.values.any((t) => !grouped.contains(t)))
        ('More', Icons.more_horiz_rounded, HuxColors.accentPink,
            [for (final t in JournalTag.values) if (!grouped.contains(t)) t]),
    ];
    final progress = (_loggedDays / 14).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(title: const Text('Daily journal')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: text.bodyMedium),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
                HuxHeroCard(
                  icon: Icons.edit_note_rounded,
                  color: HuxColors.accentPurple,
                  eyebrow: '$_loggedDays day${_loggedDays == 1 ? '' : 's'} logged',
                  title: 'What happened ${_daysAgo == 0 ? 'today' : 'yesterday'}?',
                  subtitle: 'Tap what applies. Saved automatically.',
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Today')),
                        ButtonSegment(value: 1, label: Text('Yesterday')),
                      ],
                      selected: {_daysAgo},
                      onSelectionChanged: (s) {
                        setState(() => _daysAgo = s.first);
                        _load();
                      },
                    ),
                  ),
                ),
                const SizedBox(height: HuxSpacing.lg),
                for (final g in groups) ...[
                  HuxSectionTitle(g.$1, icon: g.$2, iconColor: g.$3),
                  Wrap(
                    spacing: HuxSpacing.sm,
                    runSpacing: HuxSpacing.sm,
                    children: [
                      for (final tag in g.$4)
                        FilterChip(
                          label: Text(tag.label),
                          selected: _tags.contains(tag),
                          showCheckmark: _tags.contains(tag),
                          checkmarkColor: g.$3,
                          backgroundColor: HuxColors.card,
                          selectedColor: g.$3.withValues(alpha: 0.16),
                          side: BorderSide(color: _tags.contains(tag) ? g.$3 : HuxColors.glassStroke),
                          onSelected: (_) => _toggle(tag),
                        ),
                    ],
                  ),
                  const SizedBox(height: HuxSpacing.lg),
                ],
                const SizedBox(height: HuxSpacing.sm),
                const HuxSectionTitle('Your patterns', icon: Icons.insights_rounded),
                if (_insights.isEmpty)
                  HuxCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _loggedDays < 7
                              ? 'Log for about 2 weeks and HUX will show what chai, '
                                  'late dinners and more do to YOUR sleep. '
                                  '$_loggedDays day${_loggedDays == 1 ? '' : 's'} logged so far.'
                              : 'No clear patterns yet — keep logging. Patterns '
                                  'appear when a habit shows up on at least 3 nights.',
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: HuxSpacing.md),
                        HuxProgressBar(value: progress, color: HuxColors.accentPurple),
                      ],
                    ),
                  )
                else ...[
                  for (final insight in _insights) ...[
                    HuxCard(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const HuxIconBadge(icon: Icons.bedtime_outlined, color: HuxColors.ringSleep, size: 36),
                          const SizedBox(width: HuxSpacing.md),
                          Expanded(child: Text(insight.text, style: text.bodyMedium)),
                        ],
                      ),
                    ),
                    const SizedBox(height: HuxSpacing.sm),
                  ],
                  Text(
                    'Patterns from your own nights — not medical advice.',
                    style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
                  ),
                ],
              ],
            ),
    );
  }
}
