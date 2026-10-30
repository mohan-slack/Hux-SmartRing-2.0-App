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
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_kit.dart';
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

  void _tips(Move move) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(move.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: huxInk)),
              const SizedBox(height: 12),
              _Line(icon: Icons.south_rounded, label: 'Easier', value: move.easier),
              _Line(icon: Icons.north_rounded, label: 'Harder', value: move.harder),
              _Line(icon: Icons.front_hand_rounded, label: 'Stop if', value: move.stopIf, warn: true),
            ],
          ),
        ),
      ),
    );
  }

  static String _clock(int s) => s >= 60 ? '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}' : '$s';

  @override
  Widget build(BuildContext context) {
    final move = moveById(_step.moveId);
    final color = moveKindColor(move.kind);
    final timed = _step.seconds != null;
    final nextMove = _index + 1 < _steps.length ? moveById(_steps[_index + 1].moveId) : null;
    // While resting, the photo previews what's next.
    final shown = _resting && nextMove != null ? nextMove : move;
    final screen = MediaQuery.sizeOf(context);
    final progress = (_index + (_resting ? 1 : 0)) / _steps.length;

    return PopScope(
      canPop: _finishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: HuxColors.bg,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(widget.workout.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- the move, full width ----
            SizedBox(
              height: screen.height * 0.52,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(key: ValueKey(shown.id), child: MovePhoto(move: shown, objectSize: 150)),
                  ),
                  // Legibility for the white text: top and bottom only.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
                        stops: [0, 0.25, 0.55, 1],
                      ),
                    ),
                  ),
                  if (_resting) const ColoredBox(color: Color(0x66000000)),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 18,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_resting ? 'Rest · next up' : '${_section()} · ${_index + 1} of ${_steps.length}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xDDFFFFFF))),
                              const SizedBox(height: 4),
                              Text(shown.name,
                                  style: const TextStyle(
                                      fontSize: 30, fontWeight: FontWeight.w800, height: 1.1, color: Colors.white)),
                              if (!_resting) ...[
                                const SizedBox(height: 4),
                                Text(stepAmount(_step),
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                              ],
                            ],
                          ),
                        ),
                        if (_resting || timed)
                          Text(_clock(_left),
                              style: const TextStyle(
                                fontSize: 56,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: Colors.white,
                                fontFeatures: [FontFeature.tabularFigures()],
                              )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            LinearProgressIndicator(value: progress, minHeight: 4, color: widget.color, backgroundColor: huxTrack),

            // ---- how to do it ----
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                children: [
                  if (_resting)
                    const Text('Breathe. Shake out your arms and legs.',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: huxInk))
                  else ...[
                    for (final (i, c) in move.cues.indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 26,
                              height: 26,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                              child: Text('${i + 1}',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color.lerp(color, huxInk, 0.3))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(c, style: const TextStyle(fontSize: 16, height: 1.35, color: huxInk))),
                          ],
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Stop if ${move.stopIf[0].toLowerCase()}${move.stopIf.substring(1)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, color: HuxColors.rundown)),
                        ),
                        TextButton(onPressed: () => _tips(move), child: const Text('Easier / harder')),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ---- controls ----
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Previous move',
                      onPressed: _index == 0 ? null : _back,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: _resting
                            ? FilledButton(
                                onPressed: _next,
                                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                                child: const Text('Skip rest', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                              )
                            : timed
                                ? FilledButton.icon(
                                    onPressed: _running
                                        ? () {
                                            _timer?.cancel();
                                            setState(() => _running = false);
                                          }
                                        : _startTimer,
                                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                                    icon: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                    label: Text(_running ? 'Pause' : 'Start',
                                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                  )
                                : FilledButton.icon(
                                    onPressed: _next,
                                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                                    icon: const Icon(Icons.check_rounded),
                                    label: const Text('Done', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                  ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      tooltip: 'Skip move',
                      onPressed: _next,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
