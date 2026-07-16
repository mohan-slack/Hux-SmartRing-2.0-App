/// Modes screen — pick an event mode (Big Day, Shaadi, Exam Season),
/// set a target date, and see the active one's countdown. Deliberately
/// undesigned; a later design phase restyles this.
///
/// Talks only to [ModeService].

import 'package:flutter/material.dart';

import '../core/modes/mode.dart';
import '../core/modes/mode_service.dart';

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

class _ModesScreenState extends State<ModesScreen> {
  late Future<EventModeConfig?> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.modeService.activeConfig();
  }

  Future<void> _refresh() async {
    final next = widget.modeService.activeConfig();
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EventModeConfig?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final active = snapshot.data;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (active != null) ...[
              _ActiveModeCard(config: active, onEnd: _endMode),
              const SizedBox(height: 24),
            ],
            Text('Modes', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Aim HUX at a life moment — a target date with coaching '
              'that builds toward it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            for (final id in ModeId.values)
              _ModeListTile(
                modeId: id,
                isActive: active?.id == id,
                onTap: () => _onTapMode(id),
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
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active: ${modeName(config.id)}'
              '${config.label != null ? ' — ${config.label}' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(countdown, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onEnd, child: const Text('End mode')),
          ],
        ),
      ),
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
      child: ListTile(
        leading: Icon(_modeIcon(modeId)),
        title: Text(modeName(modeId)),
        subtitle: Text(_modeDescription(modeId)),
        trailing: isActive
            ? const Icon(Icons.check_circle, color: Colors.teal)
            : const Icon(Icons.chevron_right),
        onTap: onTap,
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
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Set up ${modeName(widget.modeId)}',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(labelText: 'Label (optional)'),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_date == null ? 'Choose a date' : _formatDate(_date!)),
            trailing: const Icon(Icons.calendar_today),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
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
