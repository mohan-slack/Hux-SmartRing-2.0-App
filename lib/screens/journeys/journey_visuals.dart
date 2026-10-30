/// Icons and colours for journeys and moves. Moves use icons until real
/// illustrations exist (docs/ROADMAP.md: own/licensed visuals).
library;

import 'package:flutter/material.dart';

import '../../core/journeys/journey_models.dart';
import '../../theme/hux_tokens.dart';

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
