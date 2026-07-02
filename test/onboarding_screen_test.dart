import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ficbatch/tabs/onboarding_screen.dart';

void main() {
  testWidgets('onboarding shows the welcome copy and core features',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OnboardingScreen(onDone: () {}),
        ),
      ),
    );

    expect(find.text('Welcome to FicBatch'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Browse & save'), findsOneWidget);
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Get Started'), findsOneWidget);
  });
}
