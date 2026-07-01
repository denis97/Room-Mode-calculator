import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/geometry/room_shape.dart';
import 'package:room_mode_calculator/core/numeric/modal_analysis.dart';

void main() {
  test('a box slice fills the whole layer; an L-shape slice has holes', () {
    // Box: every cell in a layer is inside → no nulls.
    const box = BoxShape(length: 4, width: 3, height: 2);
    final boxResult = analyzeRoomShape(box, targetPerAxis: 10, modeCount: 2);
    final boxSlice = horizontalSlice(
      boxResult.grid,
      boxResult.modes.first.field,
      1.0,
    );
    expect(boxSlice.values.length, boxSlice.nx * boxSlice.ny);
    expect(boxSlice.values.every((v) => v != null), isTrue);

    // L-shape: the notch removes cells → some nulls in the slice.
    final lShape = ExtrudedPolygonShape(
      floor: const [(0, 0), (4, 0), (4, 2), (2, 2), (2, 4), (0, 4)],
      height: 3,
    );
    final lResult = analyzeRoomShape(lShape, targetPerAxis: 10, modeCount: 2);
    final lSlice =
        horizontalSlice(lResult.grid, lResult.modes.first.field, 1.5);
    expect(lSlice.values.any((v) => v == null), isTrue);
    expect(lSlice.values.any((v) => v != null), isTrue);
  });
}
