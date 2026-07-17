// Deliberately doesn't import main.dart/root_screen.dart: those pull in
// setup_screen.dart and viewer_screen.dart, which (as of this writing) use
// a couple of Flutter/vector_math APIs (Color.toARGB32, Matrix4.
// translateByDouble/scaleByDouble) newer than this repo's locally pinned
// Flutter SDK -- a pre-existing, unrelated version mismatch (see
// `flutter analyze`) that would otherwise fail this file to compile.
// OnboardingScreen itself doesn't depend on any of that.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:room_mode_calculator/state/onboarding_providers.dart';
import 'package:room_mode_calculator/ui/app_theme.dart';
import 'package:room_mode_calculator/ui/screens/onboarding_screen.dart';

Widget _wrap(Widget child, {bool hasSeenOnboarding = false}) {
  return ProviderScope(
    overrides: [
      hasSeenOnboardingProvider.overrideWith((ref) => hasSeenOnboarding),
    ],
    child: MaterialApp(theme: buildAppTheme(), home: child),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('starts on the first page with 4 dots and a Next button',
      (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingScreen()));
    expect(find.text('Every room rings'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('Next advances through all 4 pages to "Get started"',
      (tester) async {
    await tester.pumpWidget(_wrap(const OnboardingScreen()));

    for (final title in ['Any shape you like', 'See it, hear it', 'Judge the room']) {
      await tester.tap(find.text('Next').last);
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }

    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('Skip marks onboarding as seen', (tester) async {
    final container = ProviderContainer(overrides: [
      hasSeenOnboardingProvider.overrideWith((ref) => false),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(), home: const OnboardingScreen()),
    ));

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(container.read(hasSeenOnboardingProvider), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('has_seen_onboarding'), isTrue);
  });

  testWidgets('replaying from Setup pops back instead of getting stuck',
      (tester) async {
    await tester.pumpWidget(_wrap(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OnboardingScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      hasSeenOnboarding: true,
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });
}
