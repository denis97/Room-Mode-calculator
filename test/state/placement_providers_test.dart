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

    // Single sub, corner-loaded at both endpoints: every mode fully audible.
    container.read(stereoPairProvider.notifier).state = false;
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

  test('stereo default yields a mirrored pair of sources', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(stereoPairProvider), isTrue);
    final speakers = container.read(speakersProvider);
    expect(speakers, hasLength(2));
    expect(speakers[1].fx, speakers[0].fx);
    expect(speakers[1].fy, closeTo(1 - speakers[0].fy, 1e-12));
    expect(speakers[1].fz, speakers[0].fz);

    container.read(stereoPairProvider.notifier).state = false;
    expect(container.read(speakersProvider), hasLength(1));
  });
}
