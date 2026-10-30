/// "Why 72?" — everything the old Home said in paragraphs, as a sheet:
/// each signal against your usual, what helps today, body numbers, and
/// the full explanation folded away at the bottom.
library;

import 'package:flutter/material.dart';

import '../../core/home/home_insights.dart';
import '../../core/meaning/daily_readout.dart';
import '../../core/ring/ring_models.dart';
import '../../widgets/hux/hux_kit.dart';

Future<void> showWhySheet(
  BuildContext context, {
  required DailyReadout readout,
  required HomeInsights insights,
  SleepSession? lastNight,
  double? heartRateBpm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (c, scroll) => WhySheetBody(
        readout: readout,
        insights: insights,
        lastNight: lastNight,
        heartRateBpm: heartRateBpm,
        controller: scroll,
      ),
    ),
  );
}

class WhySheetBody extends StatelessWidget {
  final DailyReadout readout;
  final HomeInsights insights;
  final SleepSession? lastNight;
  final double? heartRateBpm;
  final ScrollController? controller;

  const WhySheetBody({
    super.key,
    required this.readout,
    required this.insights,
    this.lastNight,
    this.heartRateBpm,
    this.controller,
  });

  static const _stressHigh = 50;

  @override
  Widget build(BuildContext context) {
    final charge = readout.charge?.value;
    final plan = readout.plan;
    final stress = readout.stressIndex;
    final body = <(String, String)>[
      ('Heart rate', heartRateBpm == null ? '—' : '${heartRateBpm!.round()} bpm'),
      if (lastNight?.avgHrvMs != null) ('Night HRV', '${lastNight!.avgHrvMs} ms'),
      if (stress != null) ('Stress', '$stress · est. ${stress > _stressHigh ? 'high' : 'calm'}'),
      ('Active cal', readout.activeEnergyKcal == null ? '—' : '${readout.activeEnergyKcal} kcal'),
      if (lastNight?.minSpo2Percent != null) ('Min SpO2', '${lastNight!.minSpo2Percent}%'),
      if (lastNight?.avgRespiratoryRateBrpm != null) ('Breathing', '${lastNight!.avgRespiratoryRateBrpm!.round()}/min'),
    ];

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        Row(
          children: [
            HuxChargeOrb(value: charge, size: 64, caption: '', onDark: false),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(charge == null ? 'Still learning' : 'Why $charge?',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: huxInk)),
                  const Text('vs your own last 14 days', style: TextStyle(fontSize: 15, color: huxMuted)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (insights.why.isNotEmpty) ...[
          for (final f in insights.why) _FactorRow(f),
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('below usual', style: TextStyle(fontSize: 13, color: huxMuted)),
                Text('your usual', style: TextStyle(fontSize: 13, color: huxMuted)),
                Text('above', style: TextStyle(fontSize: 13, color: huxMuted)),
              ],
            ),
          ),
        ],
        if (plan?.effort != null || plan?.bedtime != null) ...[
          const HuxTileLabel('What helps today'),
          const SizedBox(height: 10),
          Row(
            children: [
              if (plan?.effort != null)
                Expanded(child: _MiniTile(value: plan!.effort!.label, caption: 'effort ${plan.effort!.range} / 10')),
              if (plan?.effort != null && plan?.bedtime != null) const SizedBox(width: 10),
              if (plan?.bedtime != null)
                Expanded(child: _MiniTile(value: huxClock(plan!.bedtime!.bedtime.toLocal()), caption: 'bed tonight')),
            ],
          ),
          const SizedBox(height: 20),
        ],
        if (readout.actions.isNotEmpty) ...[
          const HuxTileLabel('Try today'),
          const SizedBox(height: 6),
          for (final a in readout.actions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.radio_button_unchecked_rounded, size: 18, color: huxMuted),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(a, style: const TextStyle(fontSize: 16, color: huxInk, height: 1.35))),
                ],
              ),
            ),
          const SizedBox(height: 14),
        ],
        if (body.isNotEmpty) ...[
          const HuxTileLabel('Body today'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, value) in body)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xFFF4F2F7), borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontSize: 13, color: huxMuted)),
                      Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
        ],
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: const Text('Read the full explanation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk)),
            children: [
              Text(readout.meaning, style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF3A3646))),
              if (readout.charge?.reason != null) ...[
                const SizedBox(height: 8),
                Text(readout.charge!.reason!, style: const TextStyle(fontSize: 14, color: huxMuted)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  final WhyFactor f;

  const _FactorRow(this.f);

  @override
  Widget build(BuildContext context) {
    final (bar, ink) = switch (f.tone) {
      WhyTone.good => (const Color(0xFF1FA463), const Color(0xFF17804B)),
      WhyTone.watch => (const Color(0xFFD98400), const Color(0xFFA35F00)),
      WhyTone.neutral => (const Color(0xFF9C97AB), huxMuted),
    };
    return Semantics(
      label: '${f.label}: ${f.value}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            SizedBox(width: 96, child: Text(f.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                final half = box.maxWidth / 2;
                final len = (f.offset.abs() * half).clamp(4.0, half);
                return SizedBox(
                  height: 16,
                  child: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 3,
                        child: Container(height: 10, decoration: BoxDecoration(color: huxTrack, borderRadius: BorderRadius.circular(5))),
                      ),
                      Positioned(
                        left: f.offset < 0 ? half - len : half,
                        top: 3,
                        child: Container(width: len, height: 10, decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(5))),
                      ),
                      Positioned(left: half - 1, top: 0, child: Container(width: 2, height: 16, color: const Color(0xFF6E6A7C))),
                    ],
                  ),
                );
              }),
            ),
            SizedBox(
              width: 72,
              child: Text(f.value,
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: ink)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTile extends StatelessWidget {
  final String value;
  final String caption;

  const _MiniTile({required this.value, required this.caption});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFF4F2F7), borderRadius: BorderRadius.circular(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: huxInk)),
            Text(caption, style: const TextStyle(fontSize: 14, color: huxMuted)),
          ],
        ),
      );
}
