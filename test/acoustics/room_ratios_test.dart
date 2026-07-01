import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/acoustics/room.dart';
import 'package:room_mode_calculator/core/acoustics/room_ratios.dart';

ThirdOctaveBand band(int count) =>
    ThirdOctaveBand(centerHz: 0, lowHz: 0, highHz: 0, modeCount: count);

void main() {
  group('Bonello bands', () {
    test('every in-range mode is counted exactly once', () {
      final freqs = [34.3, 42.9, 54.9, 57.2, 68.6, 80.0];
      final bands = bonelloBands(freqs, minHz: 20, maxHz: 120);
      final total = bands.fold<int>(0, (s, b) => s + b.modeCount);
      expect(total, freqs.length);
    });

    test('bands are contiguous ⅓-octaves', () {
      final bands = bonelloBands([50], minHz: 20, maxHz: 120);
      for (var i = 1; i < bands.length; i++) {
        // Each band's low edge matches the previous band's high edge.
        expect(bands[i].lowHz, closeTo(bands[i - 1].highHz, 1e-6));
      }
    });
  });

  group('Bonello criterion', () {
    test('non-decreasing mode counts satisfy the criterion', () {
      expect(bonelloSatisfied([band(0), band(1), band(2), band(2), band(4)]),
          isTrue);
    });

    test('a drop in mode count fails the criterion', () {
      expect(bonelloSatisfied([band(1), band(3), band(2)]), isFalse);
    });

    test('all-empty bands do not satisfy the criterion', () {
      expect(bonelloSatisfied([band(0), band(0)]), isFalse);
    });
  });

  group('Room proportion', () {
    test('normalizes to the shortest dimension, sorted ascending', () {
      final p = RoomProportion.fromRoom(
          const Room(length: 5, width: 4, height: 3));
      expect(p.short, 1);
      expect(p.mid, closeTo(4 / 3, 1e-9));
      expect(p.long, closeTo(5 / 3, 1e-9));
    });

    test('finds the nearest recommended ratio', () {
      // A room with proportions ~ Louden (1 : 1.4 : 1.9).
      final p = RoomProportion.fromRoom(
          const Room(length: 1.9, width: 1.4, height: 1.0));
      final (recommended, distance) = nearestRecommendedRatio(p);
      expect(recommended.name, 'Louden');
      expect(distance, lessThan(0.05));
    });
  });
}
