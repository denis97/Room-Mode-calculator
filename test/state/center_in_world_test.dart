import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/state/custom_room_providers.dart';

void main() {
  test('centerInWorld centers the polygon bounding box', () {
    // 5 x 4 rectangle centered in an 8 x 8 field: bbox should be centered,
    // i.e. minX + maxX == 8 and minY + maxY == 8.
    final centered = centerInWorld(
      const [(0, 0), (5, 0), (5, 4), (0, 4)],
      world: 8,
    );
    final xs = centered.map((v) => v.$1);
    final ys = centered.map((v) => v.$2);
    expect(xs.reduce((a, b) => a < b ? a : b) +
        xs.reduce((a, b) => a > b ? a : b), closeTo(8, 1e-9));
    expect(ys.reduce((a, b) => a < b ? a : b) +
        ys.reduce((a, b) => a > b ? a : b), closeTo(8, 1e-9));
  });

  test('centerInWorld preserves shape (edge lengths unchanged)', () {
    const raw = [(0.0, 0.0), (5.0, 0.0), (5.0, 4.0), (0.0, 4.0)];
    final centered = centerInWorld(raw, world: 8);
    // Translation only: each vertex shifted by the same offset.
    final dx = centered[0].$1 - raw[0].$1;
    final dy = centered[0].$2 - raw[0].$2;
    for (var i = 0; i < raw.length; i++) {
      expect(centered[i].$1 - raw[i].$1, closeTo(dx, 1e-9));
      expect(centered[i].$2 - raw[i].$2, closeTo(dy, 1e-9));
    }
  });
}
