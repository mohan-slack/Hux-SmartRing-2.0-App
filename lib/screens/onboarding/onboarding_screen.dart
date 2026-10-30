/// Onboarding — a few quiet questions, one per screen, all skippable.
///
/// Tap-only chips, no typing, under a minute. The answers feed the
/// personalisation engine (core/profile/personalisation_engine.dart),
/// which picks the 2–4 featured cards on Today. Every question can be
/// skipped, and "Skip all" finishes straight away with defaults.
library;

import 'package:flutter/material.dart';

import '../../core/profile/user_profile.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';

class OnboardingScreen extends StatefulWidget {
  /// Prefills the answers (when the user edits them later from Explore).
  final UserProfile initial;

  /// Called once with the final answers (possibly all skipped).
  final Future<void> Function(UserProfile profile) onDone;

  const OnboardingScreen({
    super.key,
    this.initial = const UserProfile(),
    required this.onDone,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// How an option looks as a card: its 3D object, colour and the one
/// line that says what picking it changes.
typedef _Look = (Hux3D object, Color color, String line);

/// One group of options inside a step: cards when [look] is set,
/// otherwise plain chips.
class _Group<T> {
  final String? heading;
  final List<T> options;
  final String Function(T) label;
  final bool Function(UserProfile, T) isSelected;
  final UserProfile Function(UserProfile, T) toggle;
  final _Look Function(T)? look;

  /// Cards per row (1 for options with a longer line).
  final int columns;

  const _Group({
    this.heading,
    required this.options,
    required this.label,
    required this.isSelected,
    required this.toggle,
    this.look,
    this.columns = 2,
  });
}

class _Step {
  final String title;
  final String subtitle;
  final List<_Group<Object>> groups;

  /// Shown under the options, built from the current answers.
  final Widget Function(UserProfile)? footer;

  const _Step(this.title, this.subtitle, this.groups, {this.footer});
}

/// Builds a profile field-by-field so a toggle can set a field back to
/// null (copyWith can't express "clear").
UserProfile _with(
  UserProfile p, {
  Audience? Function()? audience,
  List<Goal> Function()? goals,
  DayType? Function()? dayType,
  Diet? Function()? diet,
  FastingHabit? Function()? fasting,
  Wearable? Function()? wearable,
  CoachStyle? Function()? coachStyle,
  AppLanguage? Function()? language,
}) =>
    UserProfile(
      audience: audience != null ? audience() : p.audience,
      goals: goals != null ? goals() : p.goals,
      dayType: dayType != null ? dayType() : p.dayType,
      diet: diet != null ? diet() : p.diet,
      fasting: fasting != null ? fasting() : p.fasting,
      wearable: wearable != null ? wearable() : p.wearable,
      coachStyle: coachStyle != null ? coachStyle() : p.coachStyle,
      language: language != null ? language() : p.language,
    );

_Group<Object> _single<T extends Object>({
  String? heading,
  required List<T> options,
  required String Function(T) label,
  required T? Function(UserProfile) read,
  required UserProfile Function(UserProfile, T?) write,
  _Look Function(T)? look,
  int columns = 2,
}) =>
    _Group<Object>(
      heading: heading,
      options: options,
      label: (o) => label(o as T),
      look: look == null ? null : (o) => look(o as T),
      columns: columns,
      isSelected: (p, o) => read(p) == o,
      // Tapping the selected chip again clears it (= skip this one).
      toggle: (p, o) => write(p, read(p) == o ? null : o as T),
    );

final _steps = <_Step>[
  _Step('Who is HUX for?', 'Tips fit the person wearing it.', [
    _single<Audience>(
      options: Audience.values,
      label: (a) => a.label,
      look: (a) => switch (a) {
        Audience.me => (Hux3D.person, HuxColors.accentPink, 'Plans and tips for your own day'),
        Audience.parent => (Hux3D.parent, HuxColors.accentIndigo, 'Gentler plans, family features first'),
        Audience.family => (Hux3D.family, HuxColors.accentPurple, 'Family features first'),
      },
      read: (p) => p.audience,
      write: (p, v) => _with(p, audience: () => v),
    ),
  ]),
  _Step('What matters most?', 'Pick up to ${UserProfile.maxGoals}.', [
    _Group<Object>(
      options: Goal.values,
      label: (o) => _goalTitle(o as Goal),
      look: (o) => _goalLook(o as Goal),
      isSelected: (p, o) => p.goals.contains(o),
      toggle: (p, o) {
        final g = o as Goal;
        final goals = [...p.goals];
        if (goals.contains(g)) {
          goals.remove(g);
        } else {
          // Keep the newest picks within the limit.
          goals.add(g);
          if (goals.length > UserProfile.maxGoals) goals.removeAt(0);
        }
        return _with(p, goals: () => goals);
      },
    ),
  ]),
  _Step('What does your day look like?', 'So nudges fit your routine.', [
    _single<DayType>(
      options: DayType.values,
      label: (d) => d.label,
      look: (d) => switch (d) {
        DayType.desk => (Hux3D.laptop, HuxColors.accentIndigo, 'Sit-too-long and after-meal walk nudges'),
        DayType.nightShift => (Hux3D.moon, HuxColors.ringSleep, 'Night shift mode: day sleep counts'),
        DayType.student => (Hux3D.book, HuxColors.accentPurple, 'Exam season mode, steady sleep'),
        DayType.homemaker => (Hux3D.bowl, HuxColors.ringFood, 'Home workouts, after-meal walks'),
        DayType.fieldTravel => (Hux3D.sun, HuxColors.ringSteps, 'Air and heat alerts for your city'),
        DayType.retired => (Hux3D.steps, HuxColors.ringCharge, 'Gentle guided walks'),
      },
      read: (p) => p.dayType,
      write: (p, v) => _with(p, dayType: () => v),
    ),
  ]),
  _Step('Food habits', 'For food tips that suit you.', [
    _single<Diet>(
      heading: 'You eat',
      options: Diet.values,
      label: (d) => d.label,
      look: (d) => switch (d) {
        Diet.veg => (Hux3D.leaf, HuxColors.ringFood, 'Dal, paneer, curd ideas'),
        Diet.egg => (Hux3D.egg, HuxColors.ringHabit, 'Eggs plus veg protein'),
        Diet.nonVeg => (Hux3D.bowl, HuxColors.accentCherry, 'Chicken, fish and eggs too'),
        Diet.jain => (Hux3D.leaf, HuxColors.steady, 'Jain-friendly protein ideas'),
      },
      read: (p) => p.diet,
      write: (p, v) => _with(p, diet: () => v),
    ),
    _single<FastingHabit>(
      heading: 'Do you fast?',
      options: FastingHabit.values,
      label: (f) => f.label,
      read: (p) => p.fasting,
      write: (p, v) => _with(p, fasting: () => v),
    ),
  ]),
  _Step('What do you wear?', 'Phone only works. A wearable adds more.', footer: _wearableFooter, [
    _single<Wearable>(
      options: Wearable.values,
      label: (w) => w.label,
      look: (w) => switch (w) {
        Wearable.phoneOnly => (Hux3D.phone, HuxColors.accentPink, 'Steps, and sleep if logged'),
        Wearable.watch => (Hux3D.watch, HuxColors.accentIndigo, 'Adds heart rate, HRV, stages'),
        Wearable.band => (Hux3D.band, HuxColors.steady, 'Heart rate and sleep'),
        Wearable.ring => (Hux3D.smartRing, const Color(0xFFB98A3C), 'Best overnight readings'),
      },
      read: (p) => p.wearable,
      write: (p, v) => _with(p, wearable: () => v),
    ),
  ]),
  _Step('How should HUX talk to you?',
      'The coach can reply in your language.', [
    _single<CoachStyle>(
      heading: 'Style',
      options: CoachStyle.values,
      label: (c) => c.label,
      columns: 1,
      look: (c) => switch (c) {
        CoachStyle.coach => (Hux3D.flame, HuxColors.accentCherry, '“Short sleep. Keep today easy, bed by 10:45.”'),
        CoachStyle.dost => (Hux3D.bubble, HuxColors.accentPink, '“Rough night yaar. Easy day, early bed?”'),
        CoachStyle.amma => (Hux3D.heart, HuxColors.ringHeart, '“You slept less, beta. Rest today, eat on time.”'),
        CoachStyle.numbers => (Hux3D.chart, HuxColors.accentIndigo, '“Sleep 6h10 (−40m). Effort 4–5. Bed 10:45.”'),
      },
      read: (p) => p.coachStyle,
      write: (p, v) => _with(p, coachStyle: () => v),
    ),
    _single<AppLanguage>(
      heading: 'Coach replies in',
      options: AppLanguage.values,
      label: (l) => l.label,
      read: (p) => p.language,
      write: (p, v) => _with(p, language: () => v),
    ),
  ]),
];

String _goalTitle(Goal g) => switch (g) {
      Goal.sugarBp => 'Steadier energy',
      Goal.getFit => 'Get fit or strong',
      _ => g.label,
    };

_Look _goalLook(Goal g) => switch (g) {
      Goal.sleepBetter => (Hux3D.moon, HuxColors.ringSleep, 'Bedtime and sleep vs your usual'),
      Goal.loseWeight => (Hux3D.flame, HuxColors.accentCherry, 'Protein, steps, walks after meals'),
      Goal.getFit => (Hux3D.dumbbell, HuxColors.ringSteps, 'Daily effort, step targets, streaks'),
      Goal.lessStress => (Hux3D.leaf, HuxColors.steady, 'Journal, steady sleep, desk breaks'),
      Goal.sugarBp => (Hux3D.sun, HuxColors.ringHabit, 'Walks after meals, gentle plans'),
      Goal.activeElder => (Hux3D.steps, HuxColors.ringFood, 'Gentle guided walks'),
      Goal.cycleHealth => (Hux3D.drop, HuxColors.accentPink, 'Your phase, in your scores'),
    };

/// What HUX can read with each choice, through Apple Health or Health
/// Connect. 2 = yes, 1 = some / if the device syncs it, 0 = no.
Widget _wearableFooter(UserProfile p) => _WearableReadout(p.wearable ?? Wearable.phoneOnly);

class _WearableReadout extends StatelessWidget {
  final Wearable w;

  const _WearableReadout(this.w);

  static const _rows = ['Steps', 'Sleep', 'Heart rate', 'HRV', 'Charge'];

  List<int> get _levels => switch (w) {
        Wearable.phoneOnly => [2, 1, 0, 0, 1],
        Wearable.watch => [2, 2, 2, 2, 2],
        Wearable.band => [2, 2, 2, 1, 2],
        Wearable.ring => [1, 2, 2, 2, 2],
      };

  String _word(int i, int level) => i == 4
      ? const ['Learning', 'Basic', 'Full'][level]
      : const ['No', 'Some', 'Yes'][level];

  @override
  Widget build(BuildContext context) {
    final levels = _levels;
    return HuxTile(
      semanticLabel: [for (var i = 0; i < _rows.length; i++) '${_rows[i]}: ${_word(i, levels[i])}'].join(', '),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('With ${w.label.toLowerCase()}, HUX reads',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: huxMuted)),
            const SizedBox(height: 12),
            for (var i = 0; i < _rows.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(_rows[i], style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: huxInk)),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          for (var k = 0; k < 2; k++)
                            Expanded(
                              child: Container(
                                height: 8,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: k < levels[i] ? HuxColors.accentPink : huxTrack,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 64,
                      child: Text(_word(i, levels[i]),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: levels[i] == 0 ? huxMuted : huxInk)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
            const Text('Through Apple Health or Health Connect, when your device syncs to it.',
                style: TextStyle(fontSize: 13, height: 1.35, color: huxMuted)),
          ],
        ),
      ),
    );
  }
}

/// One option as a card: object, title, what it changes; a ring and
/// tick when picked.
class _OptionCard extends StatelessWidget {
  final String title;
  final _Look look;
  final bool selected;
  final bool wide;
  final VoidCallback? onTap;

  const _OptionCard({required this.title, required this.look, required this.selected, required this.wide, this.onTap});

  @override
  Widget build(BuildContext context) {
    final (object, color, line) = look;
    final ink = Color.lerp(color, huxInk, 0.35)!;
    return Semantics(
      button: true,
      selected: selected,
      label: '$title. $line',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? Color.alphaBlend(color.withValues(alpha: 0.14), Colors.white) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: selected ? color : Colors.transparent, width: 2),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Hux3DObject(object, color: color, size: wide ? 56 : 46),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, height: 1.2, color: selected ? ink : huxInk)),
                        const SizedBox(height: 2),
                        Text(line,
                            maxLines: wide ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 13, height: 1.3, color: huxMuted, fontStyle: wide ? FontStyle.italic : FontStyle.normal)),
                      ],
                    ),
                  ),
                  if (selected) Icon(Icons.check_circle_rounded, color: color, size: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One colour per step (same order as [_steps]).
const _stepColors = <Color>[
  HuxColors.accentPurple,
  HuxColors.ringCharge,
  HuxColors.ringSteps,
  HuxColors.ringFood,
  HuxColors.ringSleep,
  HuxColors.accentIndigo,
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  late UserProfile _profile = widget.initial;
  int _index = 0;
  bool _saving = false;

  bool get _isLast => _index == _steps.length - 1;

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onDone(_profile);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _next() {
    if (_isLast) {
      _finish();
    } else {
      setState(() => _index++);
    }
  }

  Widget _cards(_Group<Object> group) {
    final cols = group.columns;
    final rows = <Widget>[];
    for (var i = 0; i < group.options.length; i += cols) {
      if (i > 0) rows.add(const SizedBox(height: 10));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var k = 0; k < cols; k++) ...[
              if (k > 0) const SizedBox(width: 10),
              Expanded(
                child: i + k < group.options.length
                    ? _OptionCard(
                        title: group.label(group.options[i + k]),
                        look: group.look!(group.options[i + k]),
                        selected: group.isSelected(_profile, group.options[i + k]),
                        wide: cols == 1,
                        onTap: _saving
                            ? null
                            : () => setState(() => _profile = group.toggle(_profile, group.options[i + k])),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(HuxSpacing.xl, HuxSpacing.lg, HuxSpacing.xl, HuxSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_index > 0)
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _saving ? null : () => setState(() => _index--),
                    ),
                  Expanded(
                    child: Semantics(
                      label: 'Question ${_index + 1} of ${_steps.length}',
                      excludeSemantics: true,
                      child: Row(
                        children: [
                          for (var i = 0; i < _steps.length; i++)
                            Expanded(
                              child: AnimatedContainer(
                                duration: HuxMotion.base,
                                height: 6,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(HuxRadii.chip),
                                  color: i <= _index ? _stepColors[_index] : HuxColors.hairline,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _saving ? null : _finish,
                    child: const Text('Skip all'),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: HuxSpacing.xl),
                      Text('${_index + 1} of ${_steps.length}',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: HuxColors.mutedText)),
                      const SizedBox(height: HuxSpacing.xs),
                      Text(step.title,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15, color: HuxColors.ink)),
                      const SizedBox(height: HuxSpacing.sm),
                      Text(step.subtitle, style: text.bodyMedium?.copyWith(color: HuxColors.mutedText)),
                      const SizedBox(height: HuxSpacing.xl),
                      for (final group in step.groups) ...[
                        if (group.heading != null) ...[
                          Text(group.heading!, style: text.titleSmall),
                          const SizedBox(height: HuxSpacing.sm),
                        ],
                        if (group.look != null)
                          _cards(group)
                        else
                        Wrap(
                          spacing: HuxSpacing.sm,
                          runSpacing: HuxSpacing.sm,
                          children: [
                            for (final option in group.options)
                              FilterChip(
                                label: Text(group.label(option)),
                                selected: group.isSelected(_profile, option),
                                showCheckmark: group.isSelected(_profile, option),
                                checkmarkColor: _stepColors[_index],
                                backgroundColor: HuxColors.card,
                                padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.sm, vertical: HuxSpacing.sm),
                                selectedColor: _stepColors[_index].withValues(alpha: 0.14),
                                side: BorderSide(
                                  color: group.isSelected(_profile, option)
                                      ? _stepColors[_index]
                                      : HuxColors.glassStroke,
                                ),
                                onSelected: _saving
                                    ? null
                                    : (_) => setState(() => _profile = group.toggle(_profile, option)),
                              ),
                          ],
                        ),
                        const SizedBox(height: HuxSpacing.xl),
                      ],
                      if (step.footer != null) step.footer!(_profile),
                      const SizedBox(height: HuxSpacing.lg),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _saving ? null : _next,
                  child: Text(_isLast ? 'Done' : 'Next'),
                ),
              ),
              const SizedBox(height: HuxSpacing.sm),
              Center(
                child: Text(
                  'Skip any question — just tap Next.',
                  style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
