/// One icon + colour per guided plan, shared by the list, detail and
/// session player so a plan looks the same everywhere.
library;

import 'package:flutter/material.dart';

import '../../theme/hux_tokens.dart';

IconData planIcon(String id) => switch (id) {
      'first_steps' => Icons.directions_walk_rounded,
      'brisk_100' => Icons.speed_rounded,
      'interval_walk' => Icons.swap_horiz_rounded,
      'zero_to_5k' => Icons.directions_run_rounded,
      'stair_snacks' => Icons.stairs_rounded,
      'steady_strong_60' => Icons.accessibility_new_rounded,
      _ => Icons.flag_rounded,
    };

Color planColor(String id) => switch (id) {
      'first_steps' => HuxColors.ringFood,
      'brisk_100' => HuxColors.ringSteps,
      'interval_walk' => HuxColors.ringSleep,
      'zero_to_5k' => HuxColors.ringCharge,
      'stair_snacks' => HuxColors.ringHeart,
      'steady_strong_60' => HuxColors.accentPurple,
      _ => HuxColors.accentPink,
    };
