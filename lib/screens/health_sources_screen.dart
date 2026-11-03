/// Data sources: what reached HUX from Apple Health / Health Connect,
/// from which app, and what HUX does when something is missing.
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../core/ring/health_sources.dart';
import '../core/storage/health_store.dart';
import '../theme/hux_tokens.dart';
import '../widgets/hux/hux_3d.dart';
import '../widgets/hux/hux_kit.dart';

class HealthSourcesScreen extends StatefulWidget {
  final HealthStore store;

  /// Pull new data now (the normal sync); null hides the button.
  final Future<void> Function()? onSync;

  const HealthSourcesScreen({super.key, required this.store, this.onSync});

  @override
  State<HealthSourcesScreen> createState() => _HealthSourcesScreenState();
}

class _HealthSourcesScreenState extends State<HealthSourcesScreen> {
  HealthSourceReport? _r;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await HealthSourcesStore(widget.store).load();
    if (mounted) setState(() => _r = r);
  }

  Future<void> _sync() async {
    if (_syncing || widget.onSync == null) return;
    setState(() => _syncing = true);
    try {
      await widget.onSync!();
    } catch (_) {}
    await _load();
    if (mounted) setState(() => _syncing = false);
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t.toLocal());
    if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final app = Platform.isIOS ? 'Apple Health' : 'Health Connect';
    return Scaffold(
      appBar: AppBar(title: const Text('Data sources')),
      body: r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
              children: [
                Text(
                  'What your apps send to $app, and so to HUX. A band or ring only shows here if its own app '
                  'WRITES that data to $app.',
                  style: const TextStyle(fontSize: 14, height: 1.4, color: huxMuted),
                ),
                const SizedBox(height: 12),
                if (r.checkedAt == null)
                  const HuxTile(child: Text('Nothing checked yet — sync once and this fills in.'))
                else
                  for (final k in HealthKind.values) ...[
                    _Row(kind: k, s: r.of(k), ago: r.of(k).last == null ? null : _ago(r.of(k).last!)),
                    const SizedBox(height: 8),
                  ],
                if (widget.onSync != null) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _syncing ? null : _sync,
                    icon: _syncing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_rounded),
                    label: Text(_syncing ? 'Checking…' : 'Check again'),
                  ),
                ],
                const SizedBox(height: 16),
                HuxTile(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const HuxTileLabel('Missing something?'),
                      const SizedBox(height: 6),
                      Text(
                        Platform.isIOS
                            ? '1. In your band\'s app, turn on Apple Health sync.\n'
                                '2. Health app → your picture → Apps → that app → check what it may WRITE.\n'
                                '3. Health → Apps → HUX → allow it to READ everything.'
                            : '1. In your band\'s app, turn on Health Connect sync.\n'
                                '2. Settings → Health Connect → App permissions → that app → allow WRITE.\n'
                                '3. Same place → HUX → Allow all.',
                        style: const TextStyle(fontSize: 14, height: 1.5, color: huxInk),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Some apps only send steps (no sleep or heart rate) — that\'s the app\'s choice, not a HUX setting. '
                        'HUX then uses your morning check-in for sleep.',
                        style: TextStyle(fontSize: 13, height: 1.35, color: huxMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _Row extends StatelessWidget {
  final HealthKind kind;
  final KindSources s;
  final String? ago;

  const _Row({required this.kind, required this.s, this.ago});

  static Hux3D _object(HealthKind k) => switch (k) {
        HealthKind.sleep => Hux3D.moon,
        HealthKind.heartRate => Hux3D.heart,
        HealthKind.hrv => Hux3D.chart,
        HealthKind.spo2 => Hux3D.drop,
        HealthKind.breathing => Hux3D.bubble,
        HealthKind.steps => Hux3D.steps,
        HealthKind.activeEnergy => Hux3D.flame,
        HealthKind.distance => Hux3D.shoe,
      };

  @override
  Widget build(BuildContext context) {
    final ok = s.received;
    return HuxTile(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      semanticLabel: '${kind.label}: ${ok ? 'from ${s.sources.join(', ')}' : 'not received'}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Opacity(
              opacity: ok ? 1 : 0.45,
              child: Hux3DObject(_object(kind), color: ok ? HuxColors.ringFood : huxMuted, size: 36, animate: false),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(kind.label,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: huxInk)),
                      ),
                      Icon(ok ? Icons.check_circle_rounded : Icons.cancel_outlined,
                          size: 20, color: ok ? HuxColors.ringFood : huxMuted),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ok ? 'From ${s.sources.take(3).join(', ')}${ago == null ? '' : ' · last $ago'}' : 'Not received — no app sends this',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ok ? huxInk : huxMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(kind.usedFor, style: const TextStyle(fontSize: 13, height: 1.3, color: huxMuted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
