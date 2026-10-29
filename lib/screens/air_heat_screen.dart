/// Air & heat: pick your city (no location permission), see today and
/// tomorrow, the best time to walk, and optional 7 AM alerts.
library;

import 'package:flutter/material.dart';

import '../core/environment/environment_service.dart';
import '../core/environment/india_aqi.dart';
import '../core/environment/india_cities.dart';
import '../core/environment/outlook.dart';
import '../theme/hux_page.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';

class AirHeatScreen extends StatefulWidget {
  final EnvironmentService env;

  const AirHeatScreen({super.key, required this.env});

  @override
  State<AirHeatScreen> createState() => _AirHeatScreenState();
}

class _AirHeatScreenState extends State<AirHeatScreen> {
  IndiaCity? _city;
  Outlooks? _outlooks;
  bool _alerts = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    IndiaCity? city;
    var alerts = false;
    try {
      city = await widget.env.city();
      alerts = await widget.env.alertsOn();
    } catch (_) {
      // Fall through to "Choose your city" instead of an endless spinner.
    }
    if (!mounted) return;
    setState(() {
      _city = city;
      _alerts = alerts;
      _loading = city != null;
    });
    if (city != null) await _load(city);
  }

  Future<void> _load(IndiaCity city) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o = await widget.env.outlooks(city);
      if (!mounted) return;
      setState(() {
        _outlooks = o;
        _loading = false;
      });
      if (_alerts) widget.env.refreshAlert().catchError((Object _) {});
    } on EnvironmentException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _pickCity() async {
    final picked = await showModalBottomSheet<IndiaCity>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        children: [
          for (final c in indiaCities)
            ListTile(
              title: Text(c.name),
              trailing: c.name == _city?.name ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(ctx).pop(c),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await widget.env.setCity(picked);
    if (!mounted) return;
    setState(() => _city = picked);
    await _load(picked);
  }

  Future<void> _toggleAlerts(bool on) async {
    final result = await widget.env.setAlerts(on);
    if (!mounted) return;
    setState(() => _alerts = result);
    if (on && !result) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Notifications are off for HUX — turn them on in your phone Settings.'),
      ));
    } else if (result) {
      widget.env.refreshAlert().catchError((Object _) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Air & heat')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxSpacing.xxl),
        children: [
          HuxCard(
            padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
            child: HuxListRow(
              icon: Icons.location_city_rounded,
              color: HuxColors.accentIndigo,
              title: _city?.name ?? 'Choose your city',
              subtitle: 'No location permission needed',
              trailing: TextButton(onPressed: _pickCity, child: Text(_city == null ? 'Choose' : 'Change')),
            ),
          ),
          const SizedBox(height: HuxSpacing.md),
          if (_city == null)
            const HuxEmptyState(
              icon: Icons.air_rounded,
              color: HuxColors.steady,
              title: 'Pick your city to see today\'s air quality, heat, and the best time for a walk.',
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.all(HuxSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            HuxCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error!, style: text.bodyMedium),
                  TextButton(onPressed: () => _load(_city!), child: const Text('Retry')),
                ],
              ),
            )
          else if (_outlooks != null) ...[
            _DayCard(title: 'Today', o: _outlooks!.today, hero: true),
            const SizedBox(height: HuxSpacing.md),
            _DayCard(title: 'Tomorrow', o: _outlooks!.tomorrow),
          ],
          const SizedBox(height: HuxSpacing.lg),
          HuxCard(
            padding: const EdgeInsets.symmetric(horizontal: HuxSpacing.md, vertical: HuxSpacing.xs),
            child: HuxListRow(
              icon: Icons.notifications_active_outlined,
              color: HuxColors.stretched,
              title: 'Morning alert on bad air or hot days',
              subtitle: '7 AM, only when it matters. Updated each time you open HUX.',
              trailing: Switch(value: _alerts, onChanged: _city == null ? null : _toggleAlerts),
            ),
          ),
          const SizedBox(height: HuxSpacing.lg),
          Text(
            'Weather & air data: Open-Meteo.com (CC BY 4.0), air model by Copernicus CAMS. '
            'AQI is estimated from forecasts using India\'s CPCB scale — not a CPCB station '
            'reading. Heat levels follow IMD temperature thresholds as guidance, not an '
            'official IMD warning.',
            style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
          ),
        ],
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final String title;
  final DayOutlook o;
  final bool hero;

  const _DayCard({required this.title, required this.o, this.hero = false});

  Color _aqiColor(AqiCategory? c) => switch (c) {
        AqiCategory.good || AqiCategory.satisfactory => HuxColors.recharged,
        AqiCategory.moderate => HuxColors.steady,
        AqiCategory.poor => HuxColors.stretched,
        AqiCategory.veryPoor || AqiCategory.severe => HuxColors.rundown,
        null => HuxColors.learning,
      };

  Color _heatColor(HeatLevel h) => switch (h) {
        HeatLevel.none => HuxColors.recharged,
        HeatLevel.caution => HuxColors.stretched,
        HeatLevel.heatwave || HeatLevel.severe => HuxColors.rundown,
      };

  String _heatText(HeatLevel h) => switch (h) {
        HeatLevel.none => 'No heat concern',
        HeatLevel.caution => 'Hot',
        HeatLevel.heatwave => 'Heat-wave level',
        HeatLevel.severe => 'Severe heat',
      };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = _aqiColor(o.aqiCategory);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            HuxScoreRing(
              // CPCB AQI runs 0–500.
              progress: o.aqi == null ? null : (o.aqi! / 500).clamp(0.0, 1.0),
              centerText: o.aqi == null ? '—' : '${o.aqi}',
              color: color,
              size: 72,
            ),
            const SizedBox(width: HuxSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title.toUpperCase(),
                      style: text.labelSmall?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700, color: color)),
                  Text(
                    o.aqi == null ? 'Air: no data' : 'Air: ${o.aqiCategory!.label} (AQI ~${o.aqi}, est.)',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: HuxSpacing.xs),
                  Wrap(
                    spacing: HuxSpacing.sm,
                    runSpacing: HuxSpacing.xs,
                    children: [
                      HuxPill(
                        icon: Icons.thermostat_rounded,
                        label: o.maxTempC == null
                            ? 'Heat: no data'
                            : 'Up to ${o.maxTempC!.round()}°C'
                                '${o.maxFeelsC == null ? '' : ' (feels ${o.maxFeelsC!.round()}°C)'}',
                        color: _heatColor(o.heat),
                      ),
                      if (o.maxTempC != null) HuxPill(label: _heatText(o.heat), color: _heatColor(o.heat)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: HuxSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.directions_walk_rounded, size: 18, color: color),
            const SizedBox(width: HuxSpacing.sm),
            Expanded(child: Text(o.advice, style: text.bodyMedium)),
          ],
        ),
      ],
    );
    if (!hero) return HuxCard(child: body);
    return Container(
      padding: const EdgeInsets.all(HuxSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HuxRadii.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(color.withValues(alpha: 0.16), HuxColors.card), HuxColors.card],
        ),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: body,
    );
  }
}
