/// Widget tests for the hux_cards.dart catalog. Run with: flutter test
///
/// Each group checks the documented null convention (never a fabricated
/// zero), a real value renders as expected, and pumpAndSettle() never
/// hangs (every animation here is the one-shot HuxChartGrowIn builder).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/theme/hux_cards.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  group('HeroGaugeCard', () {
    testWidgets('null value renders em-dash, no unit', (tester) async {
      await tester.pumpWidget(_wrap(const HeroGaugeCard(label: 'Battery', value: null, unit: '%')));
      await tester.pumpAndSettle();

      expect(find.text('Battery'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('%'), findsNothing);
    });

    testWidgets('real value renders formatted numeral and unit', (tester) async {
      await tester.pumpWidget(_wrap(const HeroGaugeCard(label: 'Battery', value: 64, unit: '%')));
      await tester.pumpAndSettle();

      expect(find.text('64'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });
  });

  group('SliderRangeCard', () {
    testWidgets('null value shows em-dash header, no crash', (tester) async {
      await tester.pumpWidget(_wrap(const SliderRangeCard(label: 'Min SpO2', value: null, unit: '%')));
      await tester.pumpAndSettle();

      expect(find.text('Min SpO2'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('real value renders formatted numeral with unit', (tester) async {
      await tester.pumpWidget(_wrap(const SliderRangeCard(
        label: 'Min SpO2',
        value: 94,
        unit: '%',
        normalRangeMin: 90,
        normalRangeMax: 100,
      )));
      await tester.pumpAndSettle();

      expect(find.text('94'), findsOneWidget);
      expect(find.text('%'), findsOneWidget);
    });
  });

  group('RadialProgressCard', () {
    testWidgets('null pair renders em-dash for both legend rows', (tester) async {
      await tester.pumpWidget(_wrap(const RadialProgressCard(
        title: 'Sleep stage split',
        primaryValue: null,
        secondaryValue: null,
        max: 100,
        primaryLabel: 'Deep',
        secondaryLabel: 'REM',
      )));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsNWidgets(2));
    });

    testWidgets('real pair renders formatted legend values', (tester) async {
      await tester.pumpWidget(_wrap(const RadialProgressCard(
        title: 'Sleep stage split',
        primaryValue: 80,
        secondaryValue: 40,
        max: 400,
        primaryLabel: 'Deep',
        secondaryLabel: 'REM',
      )));
      await tester.pumpAndSettle();

      expect(find.text('80'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
    });

    testWidgets('a confirmed zero on one sub-value is not shown as em-dash', (tester) async {
      await tester.pumpWidget(_wrap(const RadialProgressCard(
        title: 'Sleep stage split',
        primaryValue: 0,
        secondaryValue: 40,
        max: 400,
        primaryLabel: 'Deep',
        secondaryLabel: 'REM',
      )));
      await tester.pumpAndSettle();

      expect(find.text('0'), findsOneWidget);
      expect(find.text('40'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });
  });

  group('BarVisualizerCard', () {
    testWidgets('all-null renders em-dash hero and grey stubs, no crash', (tester) async {
      await tester.pumpWidget(_wrap(const BarVisualizerCard(
        title: 'Stage breakdown',
        value: null,
        bars: [
          BarVisualizerDatum(label: 'Awake', value: null),
          BarVisualizerDatum(label: 'Light', value: null),
        ],
      )));
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
      expect(find.text('Awake'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
    });

    testWidgets('real bars render hero numeral and labels', (tester) async {
      await tester.pumpWidget(_wrap(const BarVisualizerCard(
        title: 'Stage breakdown',
        value: 420,
        unit: 'min asleep',
        bars: [
          BarVisualizerDatum(label: 'Awake', value: 10),
          BarVisualizerDatum(label: 'Light', value: 200),
          BarVisualizerDatum(label: 'Deep', value: 120),
          BarVisualizerDatum(label: 'REM', value: 90),
        ],
      )));
      await tester.pumpAndSettle();

      expect(find.text('420'), findsOneWidget);
      expect(find.text('min asleep'), findsOneWidget);
      expect(find.text('Deep'), findsOneWidget);
      expect(find.text('REM'), findsOneWidget);
    });
  });

  group('NudgeModal', () {
    testWidgets('shows title/message, primary action success pops the sheet', (tester) async {
      var called = false;
      await tester.pumpWidget(_wrap(Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => NudgeModal.show(
            context,
            title: 'Test your ring',
            message: 'Send one vibration to confirm it\'s connected.',
            icon: Icons.vibration,
            primaryLabel: 'Buzz now',
            onPrimary: () async {
              called = true;
            },
          ),
          child: const Text('open'),
        ),
      )));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Test your ring'), findsOneWidget);
      expect(find.text('Buzz now'), findsOneWidget);

      await tester.tap(find.text('Buzz now'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(find.text('Test your ring'), findsNothing);
    });

    testWidgets('primary action failure shows inline error, sheet stays open', (tester) async {
      await tester.pumpWidget(_wrap(Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => NudgeModal.show(
            context,
            title: 'Test your ring',
            message: 'Send one vibration to confirm it\'s connected.',
            icon: Icons.vibration,
            primaryLabel: 'Buzz now',
            onPrimary: () async {
              throw Exception('Not connected');
            },
          ),
          child: const Text('open'),
        ),
      )));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Buzz now'));
      await tester.pumpAndSettle();

      expect(find.text('Test your ring'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget);
    });
  });
}
