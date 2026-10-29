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
import '../../theme/hux_ui.dart';

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

/// One group of chips inside a step.
class _Group<T> {
  final String? heading;
  final List<T> options;
  final String Function(T) label;
  final bool Function(UserProfile, T) isSelected;
  final UserProfile Function(UserProfile, T) toggle;

  const _Group({
    this.heading,
    required this.options,
    required this.label,
    required this.isSelected,
    required this.toggle,
  });
}

class _Step {
  final String title;
  final String subtitle;
  final List<_Group<Object>> groups;
  const _Step(this.title, this.subtitle, this.groups);
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
}) =>
    _Group<Object>(
      heading: heading,
      options: options,
      label: (o) => label(o as T),
      isSelected: (p, o) => read(p) == o,
      // Tapping the selected chip again clears it (= skip this one).
      toggle: (p, o) => write(p, read(p) == o ? null : o as T),
    );

final _steps = <_Step>[
  _Step('Who is HUX for?', 'We tailor tips to the person using it.', [
    _single<Audience>(
      options: Audience.values,
      label: (a) => a.label,
      read: (p) => p.audience,
      write: (p, v) => _with(p, audience: () => v),
    ),
  ]),
  _Step('What matters most?', 'Pick up to ${UserProfile.maxGoals}.', [
    _Group<Object>(
      options: Goal.values,
      label: (o) => (o as Goal).label,
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
      read: (p) => p.dayType,
      write: (p, v) => _with(p, dayType: () => v),
    ),
  ]),
  _Step('Food habits', 'For food tips that suit you.', [
    _single<Diet>(
      heading: 'You eat',
      options: Diet.values,
      label: (d) => d.label,
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
  _Step('What do you wear?', 'No wearable? HUX works with just your phone.', [
    _single<Wearable>(
      options: Wearable.values,
      label: (w) => w.label,
      read: (p) => p.wearable,
      write: (p, v) => _with(p, wearable: () => v),
    ),
  ]),
  _Step('How should HUX talk to you?',
      'The app is in English for now — the coach can reply in your language. Change it any time.', [
    _single<CoachStyle>(
      heading: 'Style',
      options: CoachStyle.values,
      label: (c) => c.label,
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

/// One icon + colour per step (same order as [_steps]).
const _stepIcons = <IconData>[
  Icons.people_alt_rounded,
  Icons.flag_rounded,
  Icons.wb_sunny_rounded,
  Icons.restaurant_rounded,
  Icons.watch_rounded,
  Icons.chat_bubble_rounded,
];
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
                      HuxIconBadge(icon: _stepIcons[_index], color: _stepColors[_index], size: 56),
                      const SizedBox(height: HuxSpacing.lg),
                      Text('STEP ${_index + 1} OF ${_steps.length}',
                          style: text.labelSmall?.copyWith(
                              color: _stepColors[_index], letterSpacing: 0.8, fontWeight: FontWeight.w700)),
                      const SizedBox(height: HuxSpacing.xs),
                      Text(step.title, style: text.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: HuxSpacing.sm),
                      Text(step.subtitle, style: text.bodyMedium?.copyWith(color: HuxColors.mutedText)),
                      const SizedBox(height: HuxSpacing.xl),
                      for (final group in step.groups) ...[
                        if (group.heading != null) ...[
                          Text(group.heading!, style: text.titleSmall),
                          const SizedBox(height: HuxSpacing.sm),
                        ],
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
