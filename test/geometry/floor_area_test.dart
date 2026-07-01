import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/geometry/room_shape.dart';

void main() {
  test('floor area of a rectangle is width × depth', () {
    final rect = ExtrudedPolygonShape(
      floor: const [(0, 0), (5, 0), (5, 4), (0, 4)],
      height: 3,
    );
    expect(rect.floorArea, closeTo(20, 1e-9));
    expect(rect.extentX, closeTo(5, 1e-9));
    expect(rect.extentY, closeTo(4, 1e-9));
  });

  test('floor area of an L-shape excludes the notch', () {
    // 5x5 square (25 m²) minus the 2.5 x 2 top-right notch (5 m²) = 20 m².
    final lShape = ExtrudedPolygonShape(
      floor: const [(0, 0), (5, 0), (5, 3), (2.5, 3), (2.5, 5), (0, 5)],
      height: 3,
    );
    expect(lShape.floorArea, closeTo(20, 1e-9));
  });

  test('floor area is winding-independent', () {
    final cw = ExtrudedPolygonShape(
      floor: const [(0, 0), (0, 4), (5, 4), (5, 0)],
      height: 3,
    );
    expect(cw.floorArea, closeTo(20, 1e-9));
  });
}
