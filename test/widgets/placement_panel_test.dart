import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/state/placement_providers.dart';
import 'package:room_mode_calculator/ui/app_theme.dart';
import 'package:room_mode_calculator/ui/widgets/placement_panel.dart';

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets('renders plan, sliders, advisor chips and response curve',
      (tester) async {
    await tester.pumpWidget(_wrap(const PlacementPanel()));
    expect(find.text('Speaker height'), findsOneWidget);
    expect(find.text('Ear height'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Speaker spots'), findsOneWidget);
    expect(find.text('Listening spots'), findsOneWidget);
    expect(find.text('PREDICTED RESPONSE AT LISTENER'), findsOneWidget);
    expect(find.textContaining('σ'), findsOneWidget);
  });

  testWidgets('toggling the axis switch flips the provider', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: PlacementPanel()),
          ),
        ),
      ),
    );
    expect(container.read(placementWeightAxisProvider), isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(container.read(placementWeightAxisProvider), isTrue);
  });

  testWidgets('selecting an advisor chip starts the sweep', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: PlacementPanel()),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Speaker spots'));
    await tester.pump();
    expect(container.read(advisorModeProvider), AdvisorMode.speaker);
    // While the sweep runs, the legend row shows a progress spinner. (The
    // sweep itself is covered by plain async tests — the debounce timer and
    // compute isolate don't advance under the widget tester's fake clock.)
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Fire the debounce timer so no timer is pending when the test ends.
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('dragging on the plan moves the nearest marker',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: PlacementPanel()),
          ),
        ),
      ),
    );
    final before = container.read(speakerPosProvider);

    // The speaker marker sits at (0.12, 0.30) of the plan; drag from there.
    final plan = find.byKey(const Key('placement-plan'));
    final box = tester.getRect(plan);
    final start = Offset(
      box.left + before.fx * box.width,
      box.top + before.fy * box.height,
    );
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(40, 20));
    await gesture.up();
    await tester.pump();

    final after = container.read(speakerPosProvider);
    expect(after.fx, greaterThan(before.fx));
    expect(after.fy, greaterThan(before.fy));
    expect(container.read(listenerPosProvider).fx, 0.38);
  });
}
