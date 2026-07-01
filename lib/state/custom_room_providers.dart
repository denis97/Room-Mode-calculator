import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../core/geometry/room_shape.dart';
import '../core/numeric/modal_analysis.dart';

/// A user-defined non-rectangular room: a floor polygon (metres) extruded to a
/// height, plus the analysis settings. This is the input to the Phase 2 solver.
@immutable
class FloorPlan {
  const FloorPlan({
    required this.vertices,
    required this.height,
    required this.temperatureC,
    required this.resolution,
    required this.modeCount,
  });

  final List<(double, double)> vertices;
  final double height;
  final double temperatureC;

  /// Voxel grid resolution (cells along the longest axis).
  final int resolution;

  /// How many of the lowest modes to compute.
  final int modeCount;

  FloorPlan copyWith({
    List<(double, double)>? vertices,
    double? height,
    double? temperatureC,
    int? resolution,
    int? modeCount,
  }) {
    return FloorPlan(
      vertices: vertices ?? this.vertices,
      height: height ?? this.height,
      temperatureC: temperatureC ?? this.temperatureC,
      resolution: resolution ?? this.resolution,
      modeCount: modeCount ?? this.modeCount,
    );
  }
}

/// Runs the modal analysis for a [FloorPlan]. Top-level so it can execute in a
/// background isolate via [compute] — the eigensolver is too heavy for the UI
/// thread.
ModalAnalysisResult runFloorPlanAnalysis(FloorPlan plan) {
  final shape = ExtrudedPolygonShape(
    floor: plan.vertices,
    height: plan.height,
  );
  return analyzeRoomShape(
    shape,
    temperatureC: plan.temperatureC,
    targetPerAxis: plan.resolution,
    modeCount: plan.modeCount,
  );
}

/// The floor plan currently being edited. Starts as an L-shape to show off the
/// non-rectangular capability.
final floorPlanProvider = StateProvider<FloorPlan>((ref) {
  return const FloorPlan(
    vertices: [(0, 0), (5, 0), (5, 3), (2.5, 3), (2.5, 5), (0, 5)],
    height: AcousticDefaults.defaultHeight,
    temperatureC: AcousticDefaults.temperatureC,
    resolution: 16,
    modeCount: 8,
  );
});

/// The plan for which analysis has actually been requested (via the Compute
/// button). Editing the floor plan is free; only pressing Compute sets this and
/// triggers the solver, so vertex dragging never kicks off a solve.
final analysisRequestProvider = StateProvider<FloorPlan?>((ref) => null);

/// The modal-analysis result for the requested plan, computed in a background
/// isolate. Null until the first Compute.
final customModesProvider =
    FutureProvider<ModalAnalysisResult?>((ref) async {
  final request = ref.watch(analysisRequestProvider);
  if (request == null) return null;
  return compute(runFloorPlanAnalysis, request);
});

/// Index of the selected computed mode (for the 3D view).
final selectedCustomModeProvider = StateProvider<int?>((ref) => null);
