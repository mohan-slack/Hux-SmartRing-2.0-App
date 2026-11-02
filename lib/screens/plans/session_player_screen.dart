/// Session player: big countdown, what to do now, what's next, voice cues.
/// Time is measured from the wall clock, so it stays right even if the
/// phone locks; spoken cues need the app open (background audio is a
/// later upgrade).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/plans/plan_models.dart';
import '../../core/plans/speaker.dart';
import '../../core/plans/voice_cues.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';

class SessionPlayerScreen extends StatefulWidget {
  final Plan plan;
  final Session session;
  final CueLanguage language;
  final Speaker speaker;

  const SessionPlayerScreen({
    super.key,
    required this.plan,
    required this.session,
    required this.language,
    required this.speaker,
  });

  @override
  State<SessionPlayerScreen> createState() => _SessionPlayerScreenState();
}

class _SessionPlayerScreenState extends State<SessionPlayerScreen> {
  late final List<Cue> _cues = VoiceCues.forSession(widget.session, _lang);
  CueLanguage _lang = CueLanguage.english;
  bool _voice = true;
  bool _voiceAvailable = true;
  bool _started = false;
  bool _paused = false;
  DateTime? _startedAt;
  Duration _pausedTotal = Duration.zero;
  DateTime? _pausedAt;
  int _elapsed = 0;
  int _lastCueSecond = -1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lang = widget.language;
    () async {
      var ok = await widget.speaker.setLanguage(_lang.ttsTag);
      if (!ok && _lang != CueLanguage.english) {
        // No Hindi voice on this phone: fall back to English.
        _lang = CueLanguage.english;
        ok = await widget.speaker.setLanguage(_lang.ttsTag) || await widget.speaker.setLanguage('en-US');
      }
      if (mounted) setState(() => _voiceAvailable = ok);
    }();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.speaker.stop();
    _keepAwake(false);
    super.dispose();
  }

  /// Keeps the screen on during a session: if the phone locks in a
  /// pocket, the app is paused and voice cues stop mid-walk.
  void _keepAwake(bool on) {
    try {
      on ? WakelockPlus.enable() : WakelockPlus.disable();
    } catch (_) {
      // Not fatal — the timer still uses the wall clock.
    }
  }

  bool _finishing = false;

  void _start() {
    _keepAwake(true);
    setState(() {
      _started = true;
      _startedAt = DateTime.now();
    });
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _togglePause() {
    setState(() {
      if (_paused) {
        _pausedTotal += DateTime.now().difference(_pausedAt!);
        _pausedAt = null;
      } else {
        _pausedAt = DateTime.now();
        widget.speaker.stop();
      }
      _paused = !_paused;
    });
  }

  void _tick() {
    if (_paused || _startedAt == null) return;
    final elapsed = DateTime.now().difference(_startedAt!).inSeconds - _pausedTotal.inSeconds;
    final cues = VoiceCues.due(_cues, _lastCueSecond, elapsed);
    if (cues.isNotEmpty) {
      _lastCueSecond = elapsed;
      if (_voice && _voiceAvailable) widget.speaker.speak(cues.last.text);
    }
    setState(() => _elapsed = elapsed);
    if (SessionPosition.of(widget.session, elapsed).finished) {
      _timer?.cancel();
      _finish(true);
    }
  }

  Future<void> _finish(bool completed) async {
    _timer?.cancel();
    _keepAwake(false);
    _finishing = true;
    if (!mounted) return;
    if (completed) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Session complete'),
          content: Text('${widget.session.minutes} minutes done. Brilliant — see you next session.'),
          actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Done'))],
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(completed);
  }

  Future<void> _endEarly() async {
    // Hold the clock while the dialog is open: if the session finished
    // underneath it, its own pop closed the dialog instead of the screen.
    final wasRunning = _started && !_paused;
    if (wasRunning) _togglePause();
    final end = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End this session?'),
        content: const Text("It won't be marked done. Listen to your body — stopping is fine."),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep going')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('End')),
        ],
      ),
    );
    if (end == true) {
      _finish(false);
    } else if (wasRunning && mounted && _paused) {
      _togglePause();
    }
  }

  static String _label(SegmentKind k) => switch (k) {
        SegmentKind.warmup => 'Warm up — easy walk',
        SegmentKind.walk => 'Walk',
        SegmentKind.brisk => 'Brisk walk (~100 steps/min)',
        SegmentKind.fast => 'Fast walk',
        SegmentKind.slow => 'Easy walk',
        SegmentKind.run => 'Run',
        SegmentKind.snack => 'All-out burst',
        SegmentKind.exercise => 'Exercise',
        SegmentKind.cooldown => 'Cool down — easy walk',
      };

  static String _clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  static Color _color(SegmentKind k) => switch (k) {
        SegmentKind.warmup || SegmentKind.cooldown => HuxColors.ringFood,
        SegmentKind.walk || SegmentKind.slow => HuxColors.ringSleep,
        SegmentKind.brisk || SegmentKind.fast => HuxColors.ringSteps,
        SegmentKind.run || SegmentKind.snack => HuxColors.ringCharge,
        SegmentKind.exercise => HuxColors.accentPurple,
      };

  static Hux3D _object(SegmentKind k) => switch (k) {
        SegmentKind.warmup || SegmentKind.cooldown || SegmentKind.walk || SegmentKind.slow => Hux3D.steps,
        SegmentKind.brisk || SegmentKind.fast => Hux3D.flame,
        SegmentKind.run || SegmentKind.snack => Hux3D.heart,
        SegmentKind.exercise => Hux3D.dumbbell,
      };

  /// The talk test: how it should feel, in words anyone can check.
  static String _feel(SegmentKind k) => switch (k) {
        SegmentKind.warmup || SegmentKind.cooldown || SegmentKind.slow => 'Easy. You can chat comfortably.',
        SegmentKind.walk => 'Steady. You can talk easily.',
        SegmentKind.brisk => 'About 100 steps a minute. Talk, but not sing.',
        SegmentKind.fast => 'Fast. Short sentences only.',
        SegmentKind.run => 'Light jog. A few words at a time.',
        SegmentKind.snack => 'As hard as you safely can.',
        SegmentKind.exercise => 'Steady and controlled.',
      };

  static bool _isEffort(SegmentKind k) =>
      k == SegmentKind.brisk || k == SegmentKind.fast || k == SegmentKind.run || k == SegmentKind.snack;

  @override
  Widget build(BuildContext context) {
    final pos = SessionPosition.of(widget.session, _elapsed);
    final segs = widget.session.segments;
    final seg = segs[pos.segmentIndex];
    final hasNext = pos.segmentIndex + 1 < segs.length;
    final next = hasNext ? segs[pos.segmentIndex + 1] : null;
    final total = widget.session.totalSeconds;
    final color = _color(seg.kind);
    final left = _started ? pos.secondsLeftInSegment : seg.seconds;
    final segProgress = seg.seconds == 0 ? 0.0 : (1 - left / seg.seconds).clamp(0.0, 1.0);
    final efforts = [for (var i = 0; i < segs.length; i++) if (_isEffort(segs[i].kind)) i];
    final effortNo = efforts.indexOf(pos.segmentIndex) + 1;
    final ink = Color.lerp(color, HuxColors.ink, 0.45)!;
    final ring = (MediaQuery.sizeOf(context).height * 0.32).clamp(180.0, 270.0);

    return PopScope(
      // Back gesture mid-session asks first (it won't be marked done).
      canPop: !_started || _finishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endEarly();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        color: Color.alphaBlend(color.withValues(alpha: 0.12), HuxColors.bg),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text('Week ${widget.session.week} · Session ${widget.session.day}'),
            actions: [
              IconButton(
                tooltip: _voice ? 'Mute voice' : 'Unmute voice',
                icon: Icon(_voice ? Icons.volume_up_rounded : Icons.volume_off_rounded),
                onPressed: _voiceAvailable ? () => setState(() => _voice = !_voice) : null,
              ),
            ],
          ),
          body: SafeArea(
            // Scrolls on small phones / large text instead of overflowing.
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.lg),
                      child: Column(
                        children: [
                          // ---- whole session: one bar per segment ----
                          SizedBox(
                            height: 12,
                            child: Row(
                              children: [
                                for (var i = 0; i < segs.length; i++)
                                  Expanded(
                                    flex: segs[i].seconds.clamp(1, 1 << 20),
                                    child: Container(
                                      margin: EdgeInsets.only(right: i == segs.length - 1 ? 0 : 3),
                                      decoration: BoxDecoration(
                                        color: i < pos.segmentIndex || (i == pos.segmentIndex && _started)
                                            ? _color(segs[i].kind)
                                            : _color(segs[i].kind).withValues(alpha: 0.22),
                                        borderRadius: BorderRadius.circular(6),
                                        border: i == pos.segmentIndex
                                            ? Border.all(color: _color(segs[i].kind), width: 2)
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text('${_clock(_elapsed.clamp(0, total))} done',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: huxInk)),
                              const Spacer(),
                              Text('${_clock((total - _elapsed).clamp(0, total))} left',
                                  style: const TextStyle(fontSize: 14, color: huxMuted)),
                            ],
                          ),
                          const Spacer(),

                          // ---- now ----
                          Text(_label(seg.kind),
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: ink)),
                          const SizedBox(height: 4),
                          Text(
                            effortNo > 0 ? '${_feel(seg.kind)}  ·  $effortNo of ${efforts.length}' : _feel(seg.kind),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 15, color: huxMuted),
                          ),
                          const SizedBox(height: 18),
                          Semantics(
                            label: '$left seconds left',
                            excludeSemantics: true,
                            child: SizedBox(
                              width: ring,
                              height: ring,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  SizedBox.expand(
                                    child: CircularProgressIndicator(
                                      value: segProgress,
                                      strokeWidth: 16,
                                      strokeCap: StrokeCap.round,
                                      color: color,
                                      backgroundColor: color.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Hux3DObject(_object(seg.kind), color: color, size: ring * 0.3,
                                          animate: _started && !_paused ? null : false),
                                      Text(_clock(left),
                                          style: TextStyle(
                                            fontSize: ring * 0.22,
                                            fontWeight: FontWeight.w800,
                                            height: 1,
                                            color: huxInk,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          )),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (seg.instruction != null) ...[
                            const SizedBox(height: 14),
                            Text(seg.instruction!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 16, height: 1.35, color: huxInk)),
                          ],
                          const SizedBox(height: 18),
                          if (next != null)
                            HuxTile(
                              padding: const EdgeInsets.fromLTRB(10, 8, 16, 8),
                              child: Row(
                                children: [
                                  Hux3DObject(_object(next.kind), color: _color(next.kind), size: 44, animate: false),
                                  const SizedBox(width: 10),
                                  const Text('Next', style: TextStyle(fontSize: 14, color: huxMuted)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_label(next.kind),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk)),
                                  ),
                                  Text(_clock(next.seconds),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: huxInk)),
                                ],
                              ),
                            ),
                          if (!_voiceAvailable)
                            const Padding(
                              padding: EdgeInsets.only(top: HuxSpacing.md),
                              child: Text('No voice on this phone — follow the timer.',
                                  style: TextStyle(fontSize: 13, color: huxMuted)),
                            ),
                          const Spacer(),

                          // ---- controls ----
                          if (!_started)
                            SizedBox(
                              width: double.infinity,
                              height: 58,
                              child: FilledButton.icon(
                                onPressed: _start,
                                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text('Start · ${widget.session.minutes} min',
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                              ),
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 58,
                                    child: OutlinedButton.icon(
                                      onPressed: _endEarly,
                                      style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                                      icon: const Icon(Icons.stop_rounded),
                                      label: const Text('End'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: HuxSpacing.md),
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 58,
                                    child: FilledButton.icon(
                                      onPressed: _togglePause,
                                      style: FilledButton.styleFrom(shape: const StadiumBorder()),
                                      icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                                      label: Text(_paused ? 'Resume' : 'Pause',
                                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: HuxSpacing.sm),
                          const Text('Stop if you feel chest pain, dizziness or severe breathlessness.',
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: huxMuted)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
