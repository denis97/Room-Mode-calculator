import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/acoustics/speaker_placement.dart';
import 'package:room_mode_calculator/state/placement_providers.dart';

void main() {
  test('advisor grid is null while the advisor is off', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(advisorGridProvider.future), isNull);
  });

  test('advisor grid computes after the debounce', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(advisorModeProvider.notifier).state = AdvisorMode.speaker;
    final grid = await container.read(advisorGridProvider.future);
    expect(grid, isNotNull);
    expect(grid!.values, isNotEmpty);
    expect(grid.min, lessThanOrEqualTo(grid.max));
  });

  test('excitations and response follow the placement providers', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Corner-load both endpoints: every mode fully audible.
    const corner = PlacementPoint(fx: 0, fy: 0, fz: 0);
    container.read(speakerPosProvider.notifier).state = corner;
    container.read(listenerPosProvider.notifier).state = corner;

    final excitations = container.read(modeExcitationsProvider);
    expect(excitations, isNotEmpty);
    for (final e in excitations) {
      expect(e.audibility, closeTo(1.0, 1e-9));
    }

    final response = container.read(roomResponseProvider);
    expect(response.isEmpty, isFalse);
    expect(response.flatness, greaterThan(0));
  });
}
