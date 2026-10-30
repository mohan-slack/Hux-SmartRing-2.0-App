/// Small shared pieces for the Cycle screens.
library;

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/cycle/cycle_models.dart';
import '../../theme/hux_tokens.dart';

const cycleColor = HuxColors.accentPink;

/// Face ID / fingerprint / phone PIN for the Cycle lock.
class CycleLock {
  const CycleLock._();

  static Future<bool> available() async {
    try {
      return await LocalAuthentication().isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> unlock() async {
    try {
      return await LocalAuthentication().authenticate(localizedReason: 'Unlock Cycle');
    } catch (_) {
      return false;
    }
  }
}

/// Pick one mode — plain tiles (no deprecated Radio API).
class CycleModeList extends StatelessWidget {
  final CycleMode value;
  final ValueChanged<CycleMode> onChanged;

  const CycleModeList({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final m in CycleMode.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              m == value ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: m == value ? cycleColor : HuxColors.mutedText,
            ),
            title: Text(m.label),
            subtitle: Text(m.hint),
            selected: m == value,
            onTap: () => onChanged(m),
          ),
      ],
    );
  }
}

/// "Usual cycle: − 28 days +".
class DaysStepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const DaysStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(child: Text(label, style: text.bodyLarge)),
        IconButton(
          tooltip: 'Fewer days',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline_rounded),
        ),
        SizedBox(
          width: 64,
          child: Text('$value days', textAlign: TextAlign.center, style: text.titleSmall),
        ),
        IconButton(
          tooltip: 'More days',
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline_rounded),
        ),
      ],
    );
  }
}

/// The privacy promise, shown before set-up and at the bottom of Cycle.
class CyclePrivacyNote extends StatelessWidget {
  const CyclePrivacyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 18, color: HuxColors.mutedText),
        const SizedBox(width: HuxSpacing.sm),
        Expanded(
          child: Text(
            'Stays on this phone. Never shared, never in share cards, and never sent to the coach unless '
            'you turn that on. Estimates for wellness — not for contraception or diagnosis.',
            style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
          ),
        ),
      ],
    );
  }
}
