// Runs inside the real app process on a device/emulator (unlike
// `flutter test`, which always executes on the host Dart VM and can never
// observe Platform.isAndroid/isIOS as true -- see floor_plan_analysis_test.dart's
// own note on this). This is the actual gate for "is the native FEM solver
// really running, not silently falling back to the pure-Dart FDM path".
//
// Not wired into CI: a GitHub Actions macOS runner booting an emulator for
// this was too slow/flaky (timed out). Run manually on a connected
// device/emulator instead:
//   flutter test integration_test/native_backend_test.dart -d <device-id>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:room_mode_calculator/core/numeric/modal_analysis.dart';
import 'package:room_mode_calculator/state/custom_room_providers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final preset in roomPresets) {
    testWidgets('${preset.name} uses the native FEM solver, not the Dart FDM fallback',
        (tester) async {
      final plan = FloorPlan(
        vertices: preset.vertices,
        height: 2.5,
        temperatureC: 20.0,
        resolution: 16,
        modeCount: 6,
      );

      final result = runFloorPlanAnalysis(plan);

      expect(
        result.backend,
        SolverBackend.nativeFem,
        reason:
            'Expected the native FEM solver to handle the "${preset.name}" '
            'floor plan on this device, but it fell back to the Dart FDM '
            'solver instead -- see the device log (adb logcat / console) for '
            'the exception runFloorPlanAnalysis printed when the native call '
            'failed.',
      );
      expect(result.modes, isNotEmpty);
    });
  }
}
