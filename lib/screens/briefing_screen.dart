/// Morning briefing: one opt-in daily notification that brings people
/// back to see today's charge, plan and step goal.
library;

import 'package:flutter/material.dart';

import '../core/nudges/nudge_planner.dart';
import '../core/nudges/nudge_service.dart';
import '../theme/hux_page.dart';
import '../theme/hux_tokens.dart';

class BriefingScreen extends StatefulWidget {
  final NudgeService nudges;

  const BriefingScreen({super.key, required this.nudges});

  @override
  State<BriefingScreen> createState() => _BriefingScreenState();
}

class _BriefingScreenState extends State<BriefingScreen> {
  BriefingSettings? _s;
  bool _saving = false;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    widget.nudges
        .briefingSettings()
        .catchError((Object _) => BriefingSettings.defaults)
        .then((s) {
      if (mounted) setState(() => _s = s);
    });
  }

  Future<void> _save(BriefingSettings next) async {
    setState(() {
      _s = next;
      _saving = true;
    });
    try {
      final ok = await widget.nudges.saveBriefingSettings(next);
      final saved = await widget.nudges.briefingSettings();
      if (!mounted) return;
      setState(() {
        _s = saved;
        _denied = !ok && next.enabled;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Couldn't update the briefing — try again.")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(BriefingSettings s) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: s.at.hour, minute: s.at.minute),
    );
    if (picked != null) await _save(s.copyWith(at: TimeOfDayHm(picked.hour, picked.minute)));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = _s;
    const color = HuxColors.ringHabit;
    return Scaffold(
      appBar: AppBar(title: const Text('Morning briefing')),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
              children: [
                HuxHeroCard(
                  icon: Icons.wb_sunny_rounded,
                  color: color,
                  eyebrow: s.enabled ? 'On · ${s.at.label}' : 'Off',
                  title: 'Start each day with HUX',
                  subtitle: 'One gentle notification each morning: your charge, today\'s plan and step '
                      'goal are ready. Nothing else, and never at night.',
                ),
                const SizedBox(height: HuxSpacing.md),
                HuxCard(
                  padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
                  child: Column(
                    children: [
                      HuxListRow(
                        icon: Icons.notifications_active_outlined,
                        color: color,
                        title: 'Send my morning briefing',
                        trailing: Switch(
                          value: s.enabled,
                          onChanged: _saving ? null : (v) => _save(s.copyWith(enabled: v)),
                        ),
                      ),
                      const Divider(height: 1, color: HuxColors.hairline),
                      HuxListRow(
                        icon: Icons.schedule_rounded,
                        color: HuxColors.ringSleep,
                        title: 'Time',
                        trailing: HuxPill(label: s.at.label, color: HuxColors.ringSleep),
                        onTap: s.enabled && !_saving ? () => _pickTime(s) : null,
                      ),
                    ],
                  ),
                ),
                if (_denied) ...[
                  const SizedBox(height: HuxSpacing.sm),
                  Text(
                    'Notifications are off for HUX. Turn them on in your phone\'s Settings, then try again.',
                    style: text.bodySmall?.copyWith(color: HuxColors.stretched),
                  ),
                ],
              ],
            ),
    );
  }
}
