/// Workout player: one move at a time — what it is, how to do it (cues),
/// easier/harder versions and when to stop — with a timer for timed
/// moves and a "Done" button for rep moves. Rest screens in between.
/// Screen stays on; back asks first.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/journeys/journey_content.dart';
import '../../core/journeys/journey_models.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import 'journey_visuals.dart';

class JourneyWorkoutScreen extends StatefulWidget {
  final Workout workout;
  final Color color;

  const JourneyWorkoutScreen({super.key, required this.workout, required this.color});

  @override
  State<JourneyWorkoutScreen> createState() => _JourneyWorkoutScreenState();
}

class _JourneyWorkoutScreenState extends State<JourneyWorkoutScreen> {
  late final List<MoveStep> _steps = widget.workout.allSteps;
  int _index = 0;
  bool _resting = false;
  bool _running = false;
  int _left = 0;
  Timer? _timer;
  bool _finishing = false;

  MoveStep get _step => _steps[_index];

  @override
  void initState() {
    super.initState();
    _prepare();
    try {
      WakelockPlus.enable();
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    try {
      WakelockPlus.disable();
    } catch (_) {}
    super.dispose();
  }

  void _prepare() {
    _timer?.cancel();
    _running = false;
    _left = _resting ? _step.restSeconds : (_step.seconds ?? 0);
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _running = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_left <= 1) {
        _timer?.cancel();
        _next();
      } else {
        setState(() => _left--);
      }
    });
  }

  void _next() {
    if (!_resting && _step.restSeconds > 0) {
      setState(() {
        _resting = true;
        _prepare();
      });
      _startTimerSoon();
      return;
    }
    if (_index + 1 >= _steps.length) {
      _timer?.cancel();
      _finish();
      return;
    }
    setState(() {
      _resting = false;
      _index++;
      _prepare();
    });
  }

  // Rest counts down by itself.
  void _startTimerSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _resting) _startTimer();
      });

  void _back() {
    if (_index == 0) return;
    setState(() {
      _resting = false;
      _index--;
      _prepare();
    });
  }

  Future<void> _finish() async {
    _timer?.cancel();
    _finishing = true;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Workout done'),
        content: Text('${widget.workout.title} complete. Drink some water and stretch if anything feels tight.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Done'))],
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _confirmLeave() async {
    final was = _running;
    _timer?.cancel();
    setState(() => _running = false);
    final leave = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('End the workout?'),
        content: const Text("It won't be ticked as done. Stopping is fine if something hurts."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('End')),
        ],
      ),
    );
    if (leave == true) {
      _finishing = true;
      if (mounted) Navigator.of(context).pop(false);
    } else if (was && _left > 0) {
      _startTimer();
    }
  }

  String _section() {
    final w = widget.workout;
    final mainEnd = w.warmup.length + w.main.length * w.rounds;
    if (_index < w.warmup.length) return 'Warm-up';
    if (_index < mainEnd) {
      final round = ((_index - w.warmup.length) ~/ w.main.length) + 1;
      return w.rounds > 1 ? 'Round $round of ${w.rounds}' : 'Workout';
    }
    return 'Cool-down';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final move = moveById(_step.moveId);
    final color = moveKindColor(move.kind);
    final timed = _step.seconds != null;
    final nextMove = _index + 1 < _steps.length ? moveById(_steps[_index + 1].moveId) : null;

    return PopScope(
      canPop: _finishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.workout.title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.lg),
            children: [
              HuxProgressBar(value: (_index + (_resting ? 1 : 0)) / _steps.length, color: widget.color),
              const SizedBox(height: HuxSpacing.xs),
              Text('${_section()} · ${_index + 1} of ${_steps.length}', style: text.labelMedium),
              const SizedBox(height: HuxSpacing.lg),
              if (_resting) ...[
                Center(child: Text('Rest', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
                const SizedBox(height: HuxSpacing.lg),
                Center(
                  child: HuxScoreRing(
                    progress: _step.restSeconds == 0 ? 0 : _left / _step.restSeconds,
                    centerText: '$_left',
                    color: HuxColors.ringSleep,
                    size: 160,
                    stroke: 10,
                  ),
                ),
                const SizedBox(height: HuxSpacing.lg),
                if (nextMove != null)
                  Center(child: Text('Next: ${nextMove.name}', style: text.titleSmall)),
                const SizedBox(height: HuxSpacing.lg),
                OutlinedButton(onPressed: _next, child: const Text('Skip rest')),
              ] else ...[
                HuxCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          HuxIconBadge(icon: moveIcon(move.icon), color: color, size: 56),
                          const SizedBox(width: HuxSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(move.name, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                                Text(stepAmount(_step), style: text.titleSmall?.copyWith(color: color)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: HuxSpacing.md),
                      for (final (i, c) in move.cues.indexed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: HuxSpacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${i + 1}.  ', style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
                              Expanded(child: Text(c, style: text.bodyMedium)),
                            ],
                          ),
                        ),
                      const Divider(color: HuxColors.hairline),
                      _Line(icon: Icons.south_rounded, label: 'Easier', value: move.easier),
                      _Line(icon: Icons.north_rounded, label: 'Harder', value: move.harder),
                      _Line(icon: Icons.front_hand_rounded, label: 'Stop if', value: move.stopIf, warn: true),
                    ],
                  ),
                ),
                const SizedBox(height: HuxSpacing.lg),
                if (timed)
                  Center(
                    child: HuxScoreRing(
                      progress: _step.seconds == 0 ? 0 : 1 - _left / _step.seconds!,
                      centerText: '$_left s',
                      color: color,
                      size: 140,
                      stroke: 10,
                    ),
                  ),
                const SizedBox(height: HuxSpacing.lg),
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Previous move',
                      onPressed: _index == 0 ? null : _back,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    const SizedBox(width: HuxSpacing.md),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: timed
                            ? FilledButton.icon(
                                onPressed: _running
                                    ? () {
                                        _timer?.cancel();
                                        setState(() => _running = false);
                                      }
                                    : _startTimer,
                                icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                label: Text(_running ? 'Pause' : 'Start'),
                              )
                            : FilledButton.icon(
                                onPressed: _next,
                                icon: const Icon(Icons.check_rounded),
                                label: const Text('Done'),
                              ),
                      ),
                    ),
                    const SizedBox(width: HuxSpacing.md),
                    IconButton.filledTonal(
                      tooltip: 'Skip move',
                      onPressed: _next,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool warn;

  const _Line({required this.icon, required this.label, required this.value, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = warn ? HuxColors.rundown : HuxColors.mutedText;
    return Padding(
      padding: const EdgeInsets.only(top: HuxSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c),
          const SizedBox(width: HuxSpacing.sm),
          Text('$label: ', style: text.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: c)),
          Expanded(child: Text(value, style: text.bodySmall)),
        ],
      ),
    );
  }
}
