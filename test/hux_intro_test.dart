/// HUX intro overlay: off / quick / full-with-skip all end on the app.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/widgets/hux_intro.dart';

void main() {
  Widget app(IntroMode mode) => MaterialApp(
        home: HuxIntro(mode: mode, child: const Scaffold(body: Text('home'))),
      );
  // A getter, not a field: semantics finders need the test binding.
  Finder overlay() => find.bySemanticsLabel('HUX. Know your charge.');

  testWidgets('off: no overlay at all', (tester) async {
    await tester.pumpWidget(app(IntroMode.off));
    expect(find.text('home'), findsOneWidget);
    expect(overlay(), findsNothing);
  });

  testWidgets('quick: fades away in under a second', (tester) async {
    await tester.pumpWidget(app(IntroMode.quick));
    expect(overlay(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));
    expect(overlay(), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('full: a tap skips straight to the app', (tester) async {
    await tester.pumpWidget(app(IntroMode.full));
    await tester.pump(const Duration(milliseconds: 300));
    expect(overlay(), findsOneWidget);
    await tester.tap(overlay());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(overlay(), findsNothing);
  });
}
