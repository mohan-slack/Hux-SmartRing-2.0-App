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
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';
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
    final color = journeyColor(def.id);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 190,
            child: Stack(
              fit: StackFit.expand,
              children: [
                HuxPhoto(journeyPhoto(def.id), object: journeyObject(def.id), color: color),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xB3000000)],
                      stops: [0.45, 1],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 14,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(def.title,
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                            Text(def.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, color: Color(0xE6FFFFFF))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        children: [
                          Text('${def.days}',
                              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1, color: Colors.white)),
                          const Text('days', style: TextStyle(fontSize: 13, color: Color(0xE6FFFFFF))),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final h in def.highlights.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6, right: 10),
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        Expanded(child: Text(h, style: const TextStyle(fontSize: 15, height: 1.35, color: huxInk))),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                    child: const Text('Start', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
