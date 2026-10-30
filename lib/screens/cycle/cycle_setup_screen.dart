/// Turning Cycle on: one screen, privacy first, everything optional
/// except the "this is not contraception" OK.
library;

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../core/cycle/cycle_content.dart';
import '../../core/cycle/cycle_health_source.dart';
import '../../core/cycle/cycle_models.dart';
import '../../core/cycle/cycle_service.dart';
import '../../core/nudges/nudge_service.dart';
import '../../theme/hux_page.dart';
import '../../theme/hux_tokens.dart';
import 'cycle_widgets.dart';

String get healthAppName => Platform.isIOS ? 'Apple Health' : 'Health Connect';

class CycleSetupScreen extends StatefulWidget {
  final CycleService cycle;
  final NudgeService? nudges;

  const CycleSetupScreen({super.key, required this.cycle, this.nudges});

  @override
  State<CycleSetupScreen> createState() => _CycleSetupScreenState();
}

class _CycleSetupScreenState extends State<CycleSetupScreen> {
  CycleMode _mode = CycleMode.regular;
  int _cycleDays = 28;
  int _periodDays = 5;
  DateTime? _lastStart;
  bool _import = true;
  bool _headsUp = false;
  bool _agreed = false;
  bool _busy = false;

  Future<void> _pickDate() async {
    final today = widget.cycle.today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastStart ?? today,
      firstDate: addDays(today, -120),
      lastDate: today,
      helpText: 'First day of your last period',
    );
    if (picked != null) setState(() => _lastStart = dayOf(picked));
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final settings = CycleSettings(
      mode: _mode,
      usualCycleDays: _cycleDays,
      usualPeriodDays: _periodDays,
      headsUp: _headsUp,
    );
    String? note;
    try {
      await widget.cycle.enable(settings, lastStart: _lastStart);
      if (_import) {
        try {
          final added = await widget.cycle.importFromHealth();
          note = added > 0
              ? 'Added $added past ${added == 1 ? 'period' : 'periods'} from $healthAppName.'
              : 'No past periods found in $healthAppName.';
        } on CycleImportDenied {
          note = 'No access to $healthAppName — you can import later in Cycle settings.';
        } catch (_) {
          note = 'Could not read $healthAppName. You can try again in Cycle settings.';
        }
      }
      await widget.cycle.applyHeadsUp(widget.nudges);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(const SnackBar(content: Text('Could not save. Please try again.')));
      return;
    }
    if (!mounted) return;
    if (note != null) messenger.showSnackBar(SnackBar(content: Text(note)));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget heading(String s) => Padding(
          padding: const EdgeInsets.only(top: HuxSpacing.lg, bottom: HuxSpacing.xs),
          child: Text(s, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Set up Cycle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
        children: [
          const HuxCard(child: CyclePrivacyNote()),
          heading('Which fits you now?'),
          CycleModeList(value: _mode, onChanged: (m) => setState(() => _mode = m)),
          heading('Your last period'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_rounded, color: cycleColor),
            title: Text(_lastStart == null ? 'Pick the first day' : 'Started ${CycleContent.date(_lastStart!)}'),
            subtitle: const Text('Not sure? Skip it — log your next one instead.'),
            onTap: _pickDate,
            trailing: _lastStart == null
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _lastStart = null),
                  ),
          ),
          if (_mode.predicts) ...[
            heading('Usually'),
            DaysStepper(
              label: 'Cycle length',
              value: _cycleDays,
              min: 18,
              max: 60,
              onChanged: (v) => setState(() => _cycleDays = v),
            ),
            DaysStepper(
              label: 'Period length',
              value: _periodDays,
              min: 2,
              max: 10,
              onChanged: (v) => setState(() => _periodDays = v),
            ),
            Text('A guess is fine — HUX learns from what you log.',
                style: text.bodySmall?.copyWith(color: HuxColors.mutedText)),
          ],
          const SizedBox(height: HuxSpacing.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _import,
            onChanged: (v) => setState(() => _import = v),
            title: Text('Import past periods from $healthAppName'),
            subtitle: const Text('Read-only. Predictions work from day one.'),
          ),
          if (_mode.predicts)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _headsUp,
              onChanged: (v) => setState(() => _headsUp = v),
              title: const Text('Heads-up before your period'),
              subtitle: const Text('One quiet note, 2 days before. The lock screen only says "Heads-up from HUX".'),
            ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _agreed,
            onChanged: (v) => setState(() => _agreed = v ?? false),
            title: const Text('I understand HUX gives wellness estimates. It is not for contraception or diagnosis.'),
          ),
          const SizedBox(height: HuxSpacing.md),
          FilledButton(
            onPressed: _agreed && !_busy ? _start : null,
            child: Text(_busy ? 'Setting up…' : 'Start Cycle'),
          ),
        ],
      ),
    );
  }
}
