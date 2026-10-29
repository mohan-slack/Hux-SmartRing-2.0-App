/// Session player: big countdown, what to do now, what's next, voice cues.
/// Time is measured from the wall clock, so it stays right even if the
/// phone locks; spoken cues need the app open (background audio is a
/// later upgrade).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/plans/plan_models.dart';
import '../../core/plans/speaker.dart';
import '../../core/plans/voice_cues.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import '../../theme/hux_ui.dart';
import 'plan_visuals.dart';

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
    super.dispose();
  }

  void _start() {
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
    if (end == true) _finish(false);
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

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pos = SessionPosition.of(widget.session, _elapsed);
    final segs = widget.session.segments;
    final seg = segs[pos.segmentIndex];
    final hasNext = pos.segmentIndex + 1 < segs.length;
    final next = hasNext ? segs[pos.segmentIndex + 1] : null;
    final total = widget.session.totalSeconds;
    final color = _color(seg.kind);
    final left = _started ? pos.secondsLeftInSegment : seg.seconds;
    final segProgress = seg.seconds == 0 ? 0.0 : (1 - left / seg.seconds).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.lg),
          child: Column(
            children: [
              // ---- whole-session timeline: one bar per segment ----
              ClipRRect(
                borderRadius: BorderRadius.circular(HuxRadii.chip),
                child: SizedBox(
                  height: 10,
                  child: Row(
                    children: [
                      for (var i = 0; i < segs.length; i++)
                        Expanded(
                          flex: segs[i].seconds.clamp(1, 1 << 20),
                          child: Container(
                            margin: EdgeInsets.only(right: i == segs.length - 1 ? 0 : 2),
                            color: i < pos.segmentIndex || (i == pos.segmentIndex && _started)
                                ? _color(segs[i].kind)
                                : _color(segs[i].kind).withValues(alpha: 0.2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: HuxSpacing.sm),
              Row(
                children: [
                  Text(_clock(_elapsed.clamp(0, total)), style: text.labelMedium),
                  const Spacer(),
                  Text('${widget.plan.name} · ${_clock(total)}', style: text.labelMedium),
                ],
              ),
              const Spacer(),

              // ---- now ----
              HuxPill(label: _label(seg.kind), color: color, icon: planIcon(widget.plan.id)),
              const SizedBox(height: HuxSpacing.xl),
              Semantics(
                label: '$left seconds left',
                excludeSemantics: true,
                child: HuxScoreRing(
                  progress: segProgress,
                  centerText: _clock(left),
                  color: color,
                  size: (MediaQuery.sizeOf(context).height * 0.3).clamp(160.0, 240.0),
                  stroke: 14,
                  centerStyle: text.displayMedium?.copyWith(fontWeight: FontWeight.w700, color: HuxColors.ink),
                ),
              ),
              if (seg.instruction != null) ...[
                const SizedBox(height: HuxSpacing.lg),
                Text(seg.instruction!, style: text.bodyLarge, textAlign: TextAlign.center),
              ],
              const SizedBox(height: HuxSpacing.lg),
              if (next != null)
                HuxCard(
                  padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.sm),
                  child: Row(
                    children: [
                      HuxIconBadge(icon: Icons.skip_next_rounded, color: _color(next.kind), size: 32),
                      const SizedBox(width: HuxSpacing.sm),
                      Expanded(
                        child: Text('Next: ${_label(next.kind)} · ${_clock(next.seconds)}',
                            style: text.bodyMedium?.copyWith(color: HuxColors.mutedText)),
                      ),
                    ],
                  ),
                ),
              if (!_voiceAvailable)
                Padding(
                  padding: const EdgeInsets.only(top: HuxSpacing.md),
                  child: Text('No voice available on this phone — follow the timer.',
                      style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
                ),
              const Spacer(),

              // ---- controls ----
              if (!_started)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text('Start · ${widget.session.minutes} min'),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _endEarly,
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('End'),
                        ),
                      ),
                    ),
                    const SizedBox(width: HuxSpacing.md),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          onPressed: _togglePause,
                          icon: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                          label: Text(_paused ? 'Resume' : 'Pause'),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: HuxSpacing.sm),
              Text('Stop if you feel chest pain, dizziness or severe breathlessness.',
                  style: text.bodySmall?.copyWith(color: HuxColors.mutedText), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
