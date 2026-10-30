/// Icons, colours and photos for journeys and moves.
library;

import 'package:flutter/material.dart';

import '../../core/journeys/journey_models.dart';
import '../../theme/hux_tokens.dart';
import '../../widgets/hux/hux_3d.dart';

IconData journeyIcon(JourneyId id) => switch (id) {
      JourneyId.sleepReset21 => Icons.bedtime_rounded,
      JourneyId.fitIn30 => Icons.fitness_center_rounded,
    };

Color journeyColor(JourneyId id) => switch (id) {
      JourneyId.sleepReset21 => HuxColors.ringSleep,
      JourneyId.fitIn30 => HuxColors.ringCharge,
    };

IconData moveIcon(String name) => switch (name) {
      'walk' => Icons.directions_walk_rounded,
      'arms' => Icons.sports_gymnastics_rounded,
      'hips' => Icons.accessibility_new_rounded,
      'legs' => Icons.directions_run_rounded,
      'floor' => Icons.self_improvement_rounded,
      'push' => Icons.fitness_center_rounded,
      'squat' => Icons.airline_seat_legroom_normal_rounded,
      'stairs' => Icons.stairs_rounded,
      'jump' => Icons.sports_handball_rounded,
      'plank' => Icons.horizontal_rule_rounded,
      'stretch' => Icons.accessibility_rounded,
      'breath' => Icons.air_rounded,
      _ => Icons.circle_outlined,
    };

Color moveKindColor(MoveKind k) => switch (k) {
      MoveKind.warmup => HuxColors.ringSteps,
      MoveKind.strength => HuxColors.ringCharge,
      MoveKind.cardio => HuxColors.ringHeart,
      MoveKind.core => HuxColors.accentPurple,
      MoveKind.stretch => HuxColors.ringFood,
      MoveKind.breathing => HuxColors.ringSleep,
    };

String stepAmount(MoveStep s) => s.seconds != null
    ? (s.seconds! >= 60 && s.seconds! % 60 == 0 ? '${s.seconds! ~/ 60} min' : '${s.seconds} s')
    : '${s.reps} reps';

/// The 3D object shown for a move while its photo is missing.
Hux3D moveObject(MoveKind k) => switch (k) {
      MoveKind.warmup => Hux3D.steps,
      MoveKind.strength => Hux3D.dumbbell,
      MoveKind.cardio => Hux3D.heart,
      MoveKind.core => Hux3D.flame,
      MoveKind.stretch => Hux3D.leaf,
      MoveKind.breathing => Hux3D.bubble,
    };

/// A move's photo (assets/images/moves/<id>.jpg), cropped to fill. Until
/// a photo is added, a soft tinted panel with the move's 3D object.
class MovePhoto extends StatelessWidget {
  final Move move;
  final double objectSize;

  const MovePhoto({super.key, required this.move, this.objectSize = 140});

  @override
  Widget build(BuildContext context) {
    final color = moveKindColor(move.kind);
    final fallback = ColoredBox(
      color: Color.alphaBlend(color.withValues(alpha: 0.16), const Color(0xFFF6F4FA)),
      child: Center(child: Hux3DObject(moveObject(move.kind), color: color, size: objectSize)),
    );
    return Image.asset(
      'assets/images/moves/${move.id}.jpg',
      fit: BoxFit.cover,
      semanticLabel: move.name,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
