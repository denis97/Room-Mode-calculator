import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/geometry/room_shape.dart';
import 'package:room_mode_calculator/core/numeric/modal_analysis.dart';

void main() {
  // The numerical FDM solver must reproduce the analytical cuboid modes. Use a
  // 4x3x2 m box at c = 343 m/s with a resolution that divides the extents
  // evenly (h = 1/3 m → 12x9x6 cells), so discretization error is the only
  // source of difference.
  const box = BoxShape(length: 4, width: 3, height: 2);
  const tempForC343 = 20.0703;

  // Analytical lowest three non-zero modes (Hz):
  //   f(1,0,0) = 343 / 8      = 42.875
  //   f(0,1,0) = 343 / 6      ≈ 57.167
  //   f(1,1,0) = (343/2)·√(1/16+1/9) ≈ 71.458
  const expected = [42.875, 57.167, 71.458];

  test('FDM solver reproduces the analytical box modes within ~3%', () {
    final result = analyzeRoomShape(
      box,
      temperatureC: tempForC343,
      targetPerAxis: 12,
      modeCount: 3,
    );

    expect(result.modes.length, 3);
    for (var i = 0; i < expected.length; i++) {
      expect(
        result.modes[i].frequency,
        closeTo(expected[i], expected[i] * 0.03),
        reason: 'mode $i: got ${result.modes[i].frequency}, '
            'expected ~${expected[i]}',
      );
    }
  });

  test('computed modes are ascending with positive eigenvalues', () {
    final result = analyzeRoomShape(
      box,
      temperatureC: tempForC343,
      targetPerAxis: 12,
      modeCount: 4,
    );
    for (var i = 0; i < result.modes.length; i++) {
      expect(result.modes[i].eigenvalue, greaterThan(0));
      expect(result.modes[i].field.length, result.mesh.nodeCount);
      if (i > 0) {
        expect(result.modes[i].frequency,
            greaterThanOrEqualTo(result.modes[i - 1].frequency));
      }
    }
  });
}
