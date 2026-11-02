/// "Workout done": the moment after the last move — moves, time and an
/// estimated kcal, a medal, and a way into the Report. Calm, no confetti
/// storm; one celebration, then out of the way.
library;

import 'package:flutter/material.dart';

import '../../core/journeys/workout_log.dart';
import '../../widgets/hux/hux_3d.dart';
import '../../widgets/hux/hux_kit.dart';
import 'workout_report_screen.dart';

class WorkoutDoneScreen extends StatelessWidget {
  final WorkoutRecord record;
  final Color color;
  final WorkoutLog? log;

  /// False = kcal used the 65 kg default; we say so.
  final bool weightKnown;

  const WorkoutDoneScreen({super.key, required this.record, required this.color, this.log, this.weightKnown = true});

  static String clock(int s) => '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: huxNight,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A1A5C), huxNight],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ),
                const Spacer(),
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 190,
                        height: 190,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)]),
                        ),
                      ),
                      const Hux3DObject(Hux3D.medal, color: Color(0xFFF2B33D), size: 150),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Workout done!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
                const SizedBox(height: 6),
                Text(record.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white70)),
                const SizedBox(height: 28),
                Row(
                  children: [
                    _Stat(value: '${record.moves}', label: 'moves'),
                    const SizedBox(width: 10),
                    _Stat(value: clock(record.seconds), label: 'time'),
                    const SizedBox(width: 10),
                    _Stat(value: '≈${record.kcal.round()}', label: 'kcal'),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  weightKnown
                      ? 'Drink some water. Stretch anything that feels tight.'
                      : 'kcal estimated for ${WorkoutLog.defaultWeightKg.round()} kg — add your weight in Report for a closer number.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, height: 1.35, color: Colors.white70),
                ),
                const Spacer(),
                if (log != null) ...[
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => WorkoutReportScreen(log: log!),
                    )),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      minimumSize: const Size.fromHeight(52),
                      shape: const StadiumBorder(),
                    ),
                    icon: const Icon(Icons.insights_rounded),
                    label: const Text('See report', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: huxInk,
                    minimumSize: const Size.fromHeight(56),
                    shape: const StadiumBorder(),
                  ),
                  child: const Text('Done', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;

  const _Stat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x26FFFFFF)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  )),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
