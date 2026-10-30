/// Cycle settings: mode, usual lengths, Home card, heads-up, gentle
/// moves, coach sharing, lock, import, delete. Each change saves at once.
library;

import 'package:flutter/material.dart';

import '../../core/cycle/cycle_health_source.dart';
import '../../core/cycle/cycle_models.dart';
import '../../core/cycle/cycle_service.dart';
import '../../core/nudges/nudge_service.dart';
import '../../theme/hux_tokens.dart';
import 'cycle_setup_screen.dart' show healthAppName;
import 'cycle_widgets.dart';

class CycleSettingsScreen extends StatefulWidget {
  final CycleService cycle;
  final NudgeService? nudges;

  const CycleSettingsScreen({super.key, required this.cycle, this.nudges});

  @override
  State<CycleSettingsScreen> createState() => _CycleSettingsScreenState();
}

class _CycleSettingsScreenState extends State<CycleSettingsScreen> {
  CycleSettings? _s;
  bool _canLock = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await widget.cycle.load();
    final canLock = await CycleLock.available();
    if (!mounted) return;
    setState(() {
      _s = d.settings;
      _canLock = canLock;
    });
  }

  Future<void> _save(CycleSettings s) async {
    setState(() => _s = s);
    await widget.cycle.updateSettings(s);
    await widget.cycle.applyHeadsUp(widget.nudges);
  }

  Future<void> _setLock(bool on) async {
    // Prove it works before relying on it.
    if (on && !await CycleLock.unlock()) return;
    await _save(_s!.copyWith(lock: on));
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    String msg;
    try {
      final added = await widget.cycle.importFromHealth();
      msg = added > 0
          ? 'Added $added past ${added == 1 ? 'period' : 'periods'} from $healthAppName.'
          : 'Nothing new in $healthAppName.';
      await widget.cycle.applyHeadsUp(widget.nudges);
    } on CycleImportDenied {
      msg = 'HUX needs read access to period data in $healthAppName.';
    } catch (_) {
      msg = 'Could not read $healthAppName. Please try again.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _delete() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete all cycle data?'),
        content: const Text('Every period, symptom and setting in Cycle is removed from this phone. '
            'This cannot be undone. Data in your health app is not touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: HuxColors.rundown)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await widget.cycle.deleteAll();
    try {
      await widget.nudges?.setCycleHeadsUp(null);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop('deleted');
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final text = Theme.of(context).textTheme;
    if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: HuxSpacing.lg, bottom: HuxSpacing.xs),
          child: Text(t, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Cycle settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
        children: [
          heading('Mode'),
          CycleModeList(value: s.mode, onChanged: (m) => _save(s.copyWith(mode: m))),
          if (s.mode.predicts) ...[
            heading('Usually'),
            DaysStepper(
              label: 'Cycle length',
              value: s.usualCycleDays,
              min: 18,
              max: 60,
              onChanged: (v) => _save(s.copyWith(usualCycleDays: v)),
            ),
            DaysStepper(
              label: 'Period length',
              value: s.usualPeriodDays,
              min: 2,
              max: 10,
              onChanged: (v) => _save(s.copyWith(usualPeriodDays: v)),
            ),
          ],
          heading('Show and remind'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.showOnHome,
            onChanged: (v) => _save(s.copyWith(showOnHome: v)),
            title: const Text('Small card on Home'),
          ),
          if (s.mode.predicts)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: s.headsUp,
              onChanged: (v) => _save(s.copyWith(headsUp: v)),
              title: const Text('Heads-up before your period'),
              subtitle: const Text('Lock screen only says "Heads-up from HUX".'),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.gentleMoves,
            onChanged: (v) => _save(s.copyWith(gentleMoves: v)),
            title: const Text('Gentle workouts on period days'),
            subtitle: const Text('Journeys offer a lighter version on your first 3 days.'),
          ),
          heading('Privacy'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.useInCoach,
            onChanged: (v) => _save(s.copyWith(useInCoach: v)),
            title: const Text('Share my phase with the coach'),
            subtitle: const Text('Sends one word, like "Luteal". Never dates or symptoms.'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: s.lock,
            onChanged: _canLock ? _setLock : null,
            title: const Text('Lock Cycle'),
            subtitle: Text(_canLock
                ? 'Face ID, fingerprint or phone PIN to open. Home shows no details.'
                : 'Set a screen lock on your phone to use this.'),
          ),
          const SizedBox(height: HuxSpacing.md),
          OutlinedButton.icon(
            onPressed: _busy ? null : _import,
            icon: const Icon(Icons.download_rounded),
            label: Text('Import from $healthAppName'),
          ),
          const SizedBox(height: HuxSpacing.sm),
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline_rounded, color: HuxColors.rundown),
            label: const Text('Delete all cycle data', style: TextStyle(color: HuxColors.rundown)),
          ),
        ],
      ),
    );
  }
}
