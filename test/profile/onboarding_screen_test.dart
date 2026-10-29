/// Onboarding screen: tap through, skip all, answers reach onDone.
/// Run with: flutter test

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hux_app/core/profile/user_profile.dart';
import 'package:hux_app/screens/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('"Skip all" finishes immediately with an empty profile', (tester) async {
    UserProfile? result;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onDone: (p) async => result = p),
    ));

    await tester.tap(find.text('Skip all'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.isEmpty, isTrue);
  });

  testWidgets('answers picked on the way are passed to onDone', (tester) async {
    UserProfile? result;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onDone: (p) async => result = p),
    ));

    // Q1: who for
    await tester.tap(find.text('Me'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Q2: goals — pick two
    await tester.tap(find.text('Sleep better'));
    await tester.pump();
    await tester.tap(find.text('Less stress'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // Q3: day
    await tester.tap(find.text('Desk job'));
    await tester.pump();

    // Skip the rest.
    await tester.tap(find.text('Skip all'));
    await tester.pumpAndSettle();

    expect(result?.audience, Audience.me);
    expect(result?.goals, [Goal.sleepBetter, Goal.lessStress]);
    expect(result?.dayType, DayType.desk);
    expect(result?.diet, isNull);
  });

  testWidgets('a third goal replaces the oldest (max 2)', (tester) async {
    UserProfile? result;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onDone: (p) async => result = p),
    ));
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sleep better'));
    await tester.pump();
    await tester.tap(find.text('Lose weight'));
    await tester.pump();
    await tester.tap(find.text('Less stress'));
    await tester.pump();

    await tester.tap(find.text('Skip all'));
    await tester.pumpAndSettle();
    expect(result?.goals, [Goal.loseWeight, Goal.lessStress]);
  });
}
