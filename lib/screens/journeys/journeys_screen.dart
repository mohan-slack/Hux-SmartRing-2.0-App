/// Journeys: pick ONE guided program. If one is running, it's shown
/// first with "Continue"; switching means stopping it first.
library;

import 'package:flutter/material.dart';

import '../../core/cycle/cycle_service.dart';

import '../../core/journeys/journey_content.dart';
import '../../core/journeys/journey_models.dart';
import '../../core/journeys/journey_service.dart';
import '../../core/nudges/nudge_service.dart';
import '../../core/profile/user_profile.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import 'journey_setup_screen.dart';
import 'journey_today_screen.dart';
import 'journey_visuals.dart';

class JourneysScreen extends StatefulWidget {
  final JourneyService journeys;
  final NudgeService? nudges;

  /// From onboarding, to pre-fill the food question.
  final Diet? diet;

  /// Optional: gentle period-day options in Journeys.
  final CycleService? cycle;

  const JourneysScreen({super.key, required this.journeys, this.nudges, this.diet, this.cycle});

  @override
  State<JourneysScreen> createState() => _JourneysScreenState();
}

class _JourneysScreenState extends State<JourneysScreen> {
  JourneyState? _active;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    JourneyState? s;
    try {
      s = await widget.journeys.active();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _active = s;
      _loading = false;
    });
  }

  Future<void> _openToday() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => JourneyTodayScreen(journeys: widget.journeys, nudges: widget.nudges, cycle: widget.cycle),
    ));
    await _load();
  }

  Future<void> _start(JourneyDef def) async {
    final started = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => JourneySetupScreen(
        def: def,
        journeys: widget.journeys,
        nudges: widget.nudges,
        diet: widget.diet,
      ),
    ));
    if (started == true && mounted) {
      await _openToday();
    } else {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final active = _active;
    return Scaffold(
      appBar: AppBar(title: const Text('Journeys')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
              children: [
                Text(
                  'Guided programs for sleep, food and movement. One at a time, one quiet card a day.',
                  style: text.bodyMedium?.copyWith(color: HuxColors.mutedText),
                ),
                const SizedBox(height: HuxSpacing.lg),
                if (active != null) ...[
                  HuxHeroCard(
                    icon: journeyIcon(active.setup.id),
                    color: journeyColor(active.setup.id),
                    eyebrow: active.finished
                        ? 'Completed'
                        : active.paused
                            ? 'Paused'
                            : 'Day ${active.currentDay} of ${active.def.days}',
                    title: active.def.title,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        HuxProgressBar(
                            value: active.daysDone / active.def.days, color: journeyColor(active.setup.id)),
                        const SizedBox(height: HuxSpacing.md),
                        FilledButton(onPressed: _openToday, child: const Text('Continue')),
                      ],
                    ),
                  ),
                  const SizedBox(height: HuxSpacing.xl),
                ],
                HuxSectionTitle(active == null ? 'Choose a journey' : 'Other journeys', icon: Icons.route_rounded),
                for (final def in journeys)
                  if (def.id != active?.setup.id) ...[
                    _JourneyCard(
                      def: def,
                      onStart: active == null || active.finished ? () => _start(def) : null,
                    ),
                    const SizedBox(height: HuxSpacing.md),
                  ],
                if (active != null && !active.finished)
                  Text('One journey at a time — stop the current one to switch.',
                      style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                const SizedBox(height: HuxSpacing.lg),
                Text(
                  'Wellness programs, not medical advice. Check with a doctor before starting if you have a '
                  'health condition, are pregnant, or are recovering from an injury.',
                  style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
                ),
              ],
            ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  final JourneyDef def;
  final VoidCallback? onStart;

  const _JourneyCard({required this.def, this.onStart});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = journeyColor(def.id);
    return HuxCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HuxIconBadge(icon: journeyIcon(def.id), color: color, size: 48),
              const SizedBox(width: HuxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(def.title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(def.subtitle, style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: HuxSpacing.md),
          for (final h in def.highlights)
            Padding(
              padding: const EdgeInsets.only(bottom: HuxSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: color),
                  const SizedBox(width: HuxSpacing.sm),
                  Expanded(child: Text(h, style: text.bodySmall)),
                ],
              ),
            ),
          const SizedBox(height: HuxSpacing.sm),
          Row(
            children: [
              HuxPill(label: '${def.days} days', color: color, icon: Icons.calendar_today_rounded),
              const Spacer(),
              FilledButton(onPressed: onStart, child: const Text('Start')),
            ],
          ),
        ],
      ),
    );
  }
}
