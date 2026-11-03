/// "My month on HUX": one shareable card — active days as a big number,
/// four stats, and the month as a row of dots. Made to look good on
/// WhatsApp status / Instagram story; shows only what the user chose to
/// share by tapping Share (no health details beyond these numbers).
library;

import 'package:flutter/material.dart';

import '../core/progress/monthly_report.dart';
import '../theme/hux_tokens.dart';
import 'hux/hux_3d.dart';
import 'hux/hux_kit.dart';

class MonthCard extends StatelessWidget {
  final MonthlyReport report;
  final String monthName;

  const MonthCard({super.key, required this.report, required this.monthName});

  /// 1st, 2nd, 3rd, 4th … 11th, 12th, 13th … 21st.
  static String ordinal(int d) {
    if (d % 100 >= 11 && d % 100 <= 13) return '${d}th';
    return switch (d % 10) { 1 => '${d}st', 2 => '${d}nd', 3 => '${d}rd', _ => '${d}th' };
  }

  static String _k(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final s = report.stats;
    final days = [for (var d = 1; d <= s.days; d++) report.days[DateTime.utc(s.year, s.month, d)]];
    final best = s.bestDay;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A1A5C), huxNight],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('My $monthName on HUX',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xCCFFFFFF))),
              ),
              const Hux3DObject(Hux3D.calendar, color: HuxColors.accentPink, size: 40, animate: false),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${s.activeDays}',
                  style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800, height: 1, color: Colors.white)),
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 8),
                child: Text('of ${s.days} days\nshowing up',
                    style: const TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w600, color: Color(0xCCFFFFFF))),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // The month as dots: filled = moved, ring = logged something.
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final r in days)
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (r?.moved ?? false) ? HuxColors.ringFood : const Color(0x14FFFFFF),
                    border: Border.all(
                      color: (r?.moved ?? false)
                          ? HuxColors.ringFood
                          : (r?.active ?? false)
                              ? HuxColors.ringFood.withValues(alpha: 0.8)
                              : const Color(0x1FFFFFFF),
                      width: 1.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Stat(value: '${s.moveDays}', label: 'move days', color: HuxColors.ringFood),
              _Stat(
                value: s.medianSleepMinutes == null ? '—' : MonthlyReportBuilder.hm(s.medianSleepMinutes!),
                label: 'usual sleep',
                color: HuxColors.ringSleep,
              ),
              _Stat(value: s.medianSteps == null ? '—' : _k(s.medianSteps!), label: 'steps a day', color: HuxColors.ringSteps),
              _Stat(
                value: s.bestDaySteps == null ? '—' : _k(s.bestDaySteps!),
                label: best == null ? 'best day' : 'best (${ordinal(best.day)})',
                color: HuxColors.accentPink,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(report.headline,
              style: const TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Stat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 18, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Color(0xB3FFFFFF))),
          ],
        ),
      );
}
