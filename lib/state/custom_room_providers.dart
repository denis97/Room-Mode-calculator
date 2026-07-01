import 'dart:math' as math;

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

/// A named starting floor shape offered as a one-tap preset.
class RoomPreset {
  const RoomPreset(this.name, this.vertices);
  final String name;
  final List<(double, double)> vertices;
}

/// The editor's field size in metres (matches `FloorPlanEditor.worldSize`).
const double editorWorldSize = 8.0;

/// Shifts a polygon so its bounding box is centered in a [world]×[world] field.
List<(double, double)> centerInWorld(
  List<(double, double)> verts, {
  double world = editorWorldSize,
}) {
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  for (final (x, y) in verts) {
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  final dx = (world - (maxX - minX)) / 2 - minX;
  final dy = (world - (maxY - minY)) / 2 - minY;
  return [for (final (x, y) in verts) (x + dx, y + dy)];
}

/// Preset floor shapes (metres) for the editor.
const List<RoomPreset> roomPresets = [
  RoomPreset('Rectangle', [(0, 0), (5, 0), (5, 4), (0, 4)]),
  RoomPreset('L-shape', [(0, 0), (5, 0), (5, 3), (2.5, 3), (2.5, 5), (0, 5)]),
  RoomPreset('T-shape', [
    (1.5, 0), (3.5, 0), (3.5, 3), (5, 3), (5, 5), (0, 5), (0, 3), (1.5, 3),
  ]),
  RoomPreset('U-shape', [
    (0, 0), (5, 0), (5, 5), (3.5, 5), (3.5, 2), (1.5, 2), (1.5, 5), (0, 5),
  ]),
];

/// The floor plan currently being edited. Starts as an L-shape to show off the
/// non-rectangular capability.
final floorPlanProvider = StateProvider<FloorPlan>((ref) {
  return FloorPlan(
    vertices: centerInWorld(
      const [(0, 0), (5, 0), (5, 3), (2.5, 3), (2.5, 5), (0, 5)],
    ),
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

/// Height (metres) of the interior cross-section slice shown for the selected
/// computed mode.
final customSliceHeightProvider =
    StateProvider<double>((ref) => AcousticDefaults.earHeightM);
