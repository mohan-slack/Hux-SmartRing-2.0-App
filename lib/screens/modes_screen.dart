/// Modes screen — pick an event mode (Big Day, Shaadi, Exam Season),
/// set a target date, and see the active one's countdown. Deliberately
/// undesigned; a later design phase restyles this.
///
/// Talks only to [ModeService].

import 'package:flutter/material.dart';

import '../core/modes/mode.dart';
import '../core/modes/mode_service.dart';
import '../theme/hux_tokens.dart';

String modeName(ModeId id) => switch (id) {
      ModeId.bigDay => 'Big Day',
      ModeId.shaadi => 'Shaadi',
      ModeId.examSeason => 'Exam Season',
    };

String _modeDescription(ModeId id) => switch (id) {
      ModeId.bigDay =>
        'A presentation, interview, or match — countdown coaching '
            'for any big day.',
      ModeId.shaadi =>
        'Wedding countdown — pace yourself through the season, '
            'function by function.',
      ModeId.examSeason =>
        'Exam countdown — steady study blocks, honest about sleep '
            'versus cramming.',
    };

IconData _modeIcon(ModeId id) => switch (id) {
      ModeId.bigDay => Icons.flag,
      ModeId.shaadi => Icons.favorite,
      ModeId.examSeason => Icons.school,
    };

String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

String _formatHour(int hour24) {
  final period = hour24 >= 12 ? 'pm' : 'am';
  var h = hour24 % 12;
  if (h == 0) h = 12;
  return '$h$period';
}

/// The dropdown's SELECTION label, deliberately distinct from
/// [FastTypeDisplay.displayName]: that getter is written to read well
/// embedded in a sentence ("your fast" as a fallback for `custom`),
/// which makes it a confusing MENU ITEM — a user picking from a list
/// of {Roza, Navratri fast, Ekadashi, Karwa Chauth, your fast} can't
/// tell "your fast" means "the custom option" rather than being generic
/// placeholder text next to real choices.
String _fastTypeMenuLabel(FastType type) => switch (type) {
      FastType.roza => 'Roza',
      FastType.navratri => 'Navratri',
      FastType.ekadashi => 'Ekadashi',
      FastType.karwaChauth => 'Karwa Chauth',
      FastType.custom => 'Custom',
    };

String _fastingChipLabel(FastingConfig config, DateTime now) {
  if (config.isActiveOn(now)) {
    return '${config.type.displayName} — day ${config.dayNumberOn(now)}';
  }
  return config.type.displayName;
}

/// `targetDate` round-trips through storage as UTC (this app's usual
/// convention), but "days to go" is a local-wall-clock concept — the
/// wedding "on the 26th" means the 26th where the user is standing.
/// Converting back to local before truncating avoids landing on the
/// wrong calendar day (e.g. in IST, UTC+5:30, anything from 18:30 UTC
/// onward is already "tomorrow" locally). Same fix as
/// EventModeEngine._dateOnly.
int _daysToGo(DateTime targetDate, DateTime now) {
  final localTarget = targetDate.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(localTarget.year, localTarget.month, localTarget.day);
  return target.difference(today).inDays;
}

class ModesScreen extends StatefulWidget {
  final ModeService modeService;

  const ModesScreen({super.key, required this.modeService});

  @override
  State<ModesScreen> createState() => _ModesScreenState();
}

class _ModesData {
  final EventModeConfig? active;
  final NightShiftConfig? nightShift;
  final FastingConfig? fasting;

  const _ModesData({this.active, this.nightShift, this.fasting});
}

class _ModesScreenState extends State<ModesScreen> {
  late Future<_ModesData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ModesData> _load() async {
    final active = await widget.modeService.activeConfig();
    final nightShift = await widget.modeService.activeNightShift();
    final fasting = await widget.modeService.activeFasting();
    return _ModesData(active: active, nightShift: nightShift, fasting: fasting);
  }

  Future<void> _refresh() async {
    final next = _load();
    // Braces, not `=>`: an arrow body evaluates to the assignment's
    // value — here a Future — which setState() rejects outright.
    setState(() {
      _future = next;
    });
    await next;
  }

  Future<void> _onTapMode(ModeId id) async {
    final active = await widget.modeService.activeConfig();
    if (!mounted) return;

    if (active != null && active.id != id) {
      final replace = await _confirmReplace(active.id);
      if (replace != true) return;
    }
    if (!mounted) return;

    final setup = await showModalBottomSheet<_ModeSetup>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SetupSheet(modeId: id),
    );
    if (setup == null) return;

    await widget.modeService.startMode(EventModeConfig(
      id: id,
      targetDate: setup.targetDate,
      label: setup.label,
      startedAt: DateTime.now(),
    ));
    await _refresh();
  }

  Future<bool?> _confirmReplace(ModeId currentId) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace active mode?'),
        content: Text(
            'You already have ${modeName(currentId)} running. Starting '
            'a new mode will end it.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
  }

  Future<void> _endMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End this mode?'),
        content: const Text('You can start it again anytime.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End mode'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.modeService.endMode();
      await _refresh();
    }
  }

  Future<void> _onTapNightShift(NightShiftConfig? active) async {
    final setup = await showModalBottomSheet<NightShiftConfig>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _NightShiftSetupSheet(initial: active),
    );
    if (setup == null) return;
    await widget.modeService.startNightShift(setup);
    await _refresh();
  }

  Future<void> _endNightShift() async {
    await widget.modeService.endNightShift();
    await _refresh();
  }

  Future<void> _onTapFasting(FastingConfig? active) async {
    final setup = await showModalBottomSheet<FastingConfig>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FastingSetupSheet(initial: active),
    );
    if (setup == null) return;
    await widget.modeService.startFasting(setup);
    await _refresh();
  }

  Future<void> _endFasting() async {
    await widget.modeService.endFasting();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ModesData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data ?? const _ModesData();
        final active = data.active;
        final now = DateTime.now();

        return ListView(
          padding: const EdgeInsets.all(HuxSpacing.lg),
          children: [
            if (active != null) ...[
              _ActiveModeCard(config: active, onEnd: _endMode),
              const SizedBox(height: HuxSpacing.xl),
            ],
            if (data.nightShift != null || data.fasting != null) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (data.nightShift != null)
                    InputChip(
                      label: const Text('Night shift'),
                      onDeleted: _endNightShift,
                    ),
                  if (data.fasting != null)
                    InputChip(
                      label: Text(_fastingChipLabel(data.fasting!, now)),
                      onDeleted: _endFasting,
                    ),
                ],
              ),
              const SizedBox(height: HuxSpacing.xl),
            ],
            Text('Modes', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: HuxSpacing.xs),
            Text(
              'Aim HUX at a life moment — a target date with coaching '
              'that builds toward it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: HuxSpacing.lg),
            for (final id in ModeId.values)
              _ModeListTile(
                modeId: id,
                isActive: active?.id == id,
                onTap: () => _onTapMode(id),
              ),
            const SizedBox(height: HuxSpacing.xl),
            Text('Lifestyle', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: HuxSpacing.xs),
            Text(
              'How you live day to day — changes the app\'s voice and '
              'advice while active, no target date to count down to.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: HuxSpacing.lg),
            _LifestyleTile(
              icon: Icons.bedtime,
              title: 'Night Shift',
              description: 'Main sleep happens in the daytime — swaps '
                  '"last night" wording for "last sleep" throughout '
                  'the app.',
              isActive: data.nightShift != null,
              onTap: () => _onTapNightShift(data.nightShift),
            ),
            _LifestyleTile(
              icon: Icons.wb_twilight,
              title: 'Fasting Companion',
              description: 'A dated observance — Roza, Navratri, '
                  'Ekadashi, Karwa Chauth, or your own — adapts food-'
                  'timing advice while it runs.',
              isActive: data.fasting != null,
              onTap: () => _onTapFasting(data.fasting),
            ),
          ],
        );
      },
    );
  }
}

class _ActiveModeCard extends StatelessWidget {
  final EventModeConfig config;
  final VoidCallback onEnd;

  const _ActiveModeCard({required this.config, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    final daysToGo = _daysToGo(config.targetDate, DateTime.now());
    final countdown = daysToGo > 0
        ? '$daysToGo day${daysToGo == 1 ? '' : 's'} to go'
        : daysToGo == 0
            ? "It's today"
            : 'Wrapping up';

    return Card(
      color: HuxColors.accentMint.withValues(alpha: HuxOpacity.activeCardWash),
      child: Padding(
        padding: const EdgeInsets.all(HuxSpacing.lg),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AccentIconChip(icon: _modeIcon(config.id)),
            const SizedBox(width: HuxSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Active: ${modeName(config.id)}'
                    '${config.label != null ? ' — ${config.label}' : ''}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: HuxSpacing.xs),
                  Text(countdown,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: HuxSpacing.md),
                  OutlinedButton(
                      onPressed: onEnd, child: const Text('End mode')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shared accent treatment for a mode/lifestyle icon — one
/// consistent brand accent (mint backdrop, deep-teal glyph), not a
/// different invented color per mode. See [HuxModeAccent].
class _AccentIconChip extends StatelessWidget {
  final IconData icon;

  const _AccentIconChip({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: huxMinTapTarget,
      height: huxMinTapTarget,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: HuxModeAccent.background.withValues(alpha: HuxOpacity.iconChip),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: HuxModeAccent.foreground),
    );
  }
}

class _ModeListTile extends StatelessWidget {
  final ModeId modeId;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeListTile({
    required this.modeId,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isActive
          ? HuxColors.accentMint.withValues(alpha: HuxOpacity.activeCardWash)
          : null,
      child: ListTile(
        leading: _AccentIconChip(icon: _modeIcon(modeId)),
        title: Text(modeName(modeId)),
        subtitle: Text(_modeDescription(modeId)),
        trailing: isActive
            ? const Icon(Icons.check_circle, color: HuxColors.accentDeepTeal)
            : const Icon(Icons.chevron_right, color: HuxColors.mutedText),
        onTap: onTap,
      ),
    );
  }
}

class _LifestyleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isActive;
  final VoidCallback onTap;

  const _LifestyleTile({
    required this.icon,
    required this.title,
    required this.description,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isActive
          ? HuxColors.accentMint.withValues(alpha: HuxOpacity.activeCardWash)
          : null,
      child: ListTile(
        leading: _AccentIconChip(icon: icon),
        title: Text(title),
        subtitle: Text(description),
        trailing: isActive
            ? const Icon(Icons.check_circle, color: HuxColors.accentDeepTeal)
            : const Icon(Icons.chevron_right, color: HuxColors.mutedText),
        onTap: onTap,
      ),
    );
  }
}

class _NightShiftSetupSheet extends StatefulWidget {
  final NightShiftConfig? initial;

  const _NightShiftSetupSheet({this.initial});

  @override
  State<_NightShiftSetupSheet> createState() => _NightShiftSetupSheetState();
}

class _NightShiftSetupSheetState extends State<_NightShiftSetupSheet> {
  int? _startHour;
  int? _endHour;

  @override
  void initState() {
    super.initState();
    _startHour = widget.initial?.usualSleepStartHour;
    _endHour = widget.initial?.usualSleepEndHour;
  }

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _startHour ?? 8, minute: 0),
    );
    if (picked != null) setState(() => _startHour = picked.hour);
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _endHour ?? 16, minute: 0),
    );
    if (picked != null) setState(() => _endHour = picked.hour);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: HuxSpacing.lg,
        right: HuxSpacing.lg,
        top: HuxSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + HuxSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set up Night Shift',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: HuxSpacing.sm),
          Text(
            'Your main sleep happens in the daytime — HUX will say '
            '"last sleep" instead of "last night" throughout the app '
            'while this is on.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: HuxSpacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_startHour == null
                ? 'Usual sleep start'
                : 'Usual sleep start: ${_formatHour(_startHour!)}'),
            trailing: const Icon(Icons.access_time),
            onTap: _pickStart,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_endHour == null
                ? 'Usual sleep end'
                : 'Usual sleep end: ${_formatHour(_endHour!)}'),
            trailing: const Icon(Icons.access_time),
            onTap: _pickEnd,
          ),
          const SizedBox(height: HuxSpacing.lg),
          FilledButton(
            onPressed: (_startHour == null || _endHour == null)
                ? null
                : () {
                    Navigator.pop(
                      context,
                      NightShiftConfig(
                        usualSleepStartHour: _startHour!,
                        usualSleepEndHour: _endHour!,
                        startedAt: DateTime.now(),
                      ),
                    );
                  },
            child: const Text('Start Night Shift'),
          ),
        ],
      ),
    );
  }
}

class _FastingSetupSheet extends StatefulWidget {
  final FastingConfig? initial;

  const _FastingSetupSheet({this.initial});

  @override
  State<_FastingSetupSheet> createState() => _FastingSetupSheetState();
}

class _FastingSetupSheetState extends State<_FastingSetupSheet> {
  FastType _type = FastType.roza;
  DateTime? _start;
  DateTime? _end;
  bool _hasWindow = false;
  int? _windowStartHour;
  int? _windowEndHour;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _type = initial.type;
      _start = initial.start;
      _end = initial.end;
      _hasWindow = initial.eatingWindowStartHour != null &&
          initial.eatingWindowEndHour != null;
      _windowStartHour = initial.eatingWindowStartHour;
      _windowEndHour = initial.eatingWindowEndHour;
    }
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _start ?? now,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _start = picked;
      if (_end != null && _end!.isBefore(picked)) _end = picked;
    });
  }

  Future<void> _pickEnd() async {
    final base = _start ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _end ?? base,
      firstDate: base,
      lastDate: base.add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _end = picked);
  }

  Future<void> _pickWindowStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _windowStartHour ?? 18, minute: 0),
    );
    if (picked != null) setState(() => _windowStartHour = picked.hour);
  }

  Future<void> _pickWindowEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _windowEndHour ?? 4, minute: 0),
    );
    if (picked != null) setState(() => _windowEndHour = picked.hour);
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _start != null &&
        _end != null &&
        (!_hasWindow || (_windowStartHour != null && _windowEndHour != null));

    return Padding(
      padding: EdgeInsets.only(
        left: HuxSpacing.lg,
        right: HuxSpacing.lg,
        top: HuxSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + HuxSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set up Fasting Companion',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: HuxSpacing.lg),
            DropdownButtonFormField<FastType>(
              value: _type,
              decoration: const InputDecoration(labelText: 'Which fast'),
              items: [
                for (final type in FastType.values)
                  DropdownMenuItem(
                      value: type, child: Text(_fastTypeMenuLabel(type))),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _type = value);
              },
            ),
            const SizedBox(height: HuxSpacing.lg),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_start == null ? 'Start date' : _formatDate(_start!)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickStart,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_end == null ? 'End date' : _formatDate(_end!)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickEnd,
            ),
            const SizedBox(height: HuxSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Set an eating window (optional)'),
              value: _hasWindow,
              onChanged: (value) => setState(() => _hasWindow = value),
            ),
            if (_hasWindow) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_windowStartHour == null
                    ? 'Window opens'
                    : 'Window opens: ${_formatHour(_windowStartHour!)}'),
                trailing: const Icon(Icons.access_time),
                onTap: _pickWindowStart,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_windowEndHour == null
                    ? 'Window closes'
                    : 'Window closes: ${_formatHour(_windowEndHour!)}'),
                trailing: const Icon(Icons.access_time),
                onTap: _pickWindowEnd,
              ),
            ],
            const SizedBox(height: HuxSpacing.lg),
            FilledButton(
              onPressed: !canStart
                  ? null
                  : () {
                      Navigator.pop(
                        context,
                        FastingConfig(
                          type: _type,
                          start: _start!,
                          end: _end!,
                          eatingWindowStartHour:
                              _hasWindow ? _windowStartHour : null,
                          eatingWindowEndHour:
                              _hasWindow ? _windowEndHour : null,
                          startedAt: DateTime.now(),
                        ),
                      );
                    },
              child: const Text('Start Fasting Companion'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeSetup {
  final DateTime targetDate;
  final String? label;

  const _ModeSetup({required this.targetDate, this.label});
}

class _SetupSheet extends StatefulWidget {
  final ModeId modeId;

  const _SetupSheet({required this.modeId});

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  DateTime? _date;
  final _labelController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 14)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: HuxSpacing.lg,
        right: HuxSpacing.lg,
        top: HuxSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + HuxSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set up ${modeName(widget.modeId)}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: HuxSpacing.lg),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(labelText: 'Label (optional)'),
          ),
          const SizedBox(height: HuxSpacing.lg),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_date == null ? 'Choose a date' : _formatDate(_date!)),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          const SizedBox(height: HuxSpacing.lg),
          FilledButton(
            onPressed: _date == null
                ? null
                : () {
                    final label = _labelController.text.trim();
                    Navigator.pop(
                      context,
                      _ModeSetup(
                        targetDate: _date!,
                        label: label.isEmpty ? null : label,
                      ),
                    );
                  },
            child: const Text('Start mode'),
          ),
        ],
      ),
    );
  }
}
