import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/state/custom_room_providers.dart';

void main() {
  // `flutter test` always runs this on the host Dart VM, never on an actual
  // Android/iOS device/emulator (Platform.isAndroid is unconditionally false
  // here) -- so runFloorPlanAnalysis always takes its Dart FDM fallback path
  // in this suite, by design, not because anything is broken. That's exactly
  // why this test only checks the *numbers*, not which backend produced
  // them: for whether the *native* solver specifically is actually running
  // on-device, see integration_test/native_backend_test.dart, which runs
  // inside the real app process on a device/emulator where Platform.isAndroid
  // is meaningful.
  test('a rectangular floor plan reproduces the analytical box modes', () {
    // The same 4x3x2 box as box_modes_test, but expressed as an extruded
    // rectangle polygon and run through the FloorPlan -> solver path.
    const plan = FloorPlan(
      vertices: [(0, 0), (4, 0), (4, 3), (0, 3)],
      height: 2,
      temperatureC: 20.0703, // c ≈ 343 m/s
      resolution: 12,
      modeCount: 3,
    );

    final result = runFloorPlanAnalysis(plan);
    const expected = [42.875, 57.167, 71.458];

    expect(result.modes.length, 3);
    for (var i = 0; i < expected.length; i++) {
      expect(
        result.modes[i].frequency,
        closeTo(expected[i], expected[i] * 0.03),
        reason: 'mode $i: got ${result.modes[i].frequency}',
      );
    }
  });
}
