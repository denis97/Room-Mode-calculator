import 'dart:typed_data';

import 'mode.dart';
import 'pressure_field.dart';
import 'room.dart';
import 'room_response.dart';
import 'speaker_placement.dart';

/// Placement-advisor heatmap: response flatness over a grid of candidate
/// positions for one endpoint (speaker or listener) while the other stays
/// fixed. The modal sum is reciprocal — swapping source and receiver leaves
/// the response unchanged — so a single sweep serves both the "where should
/// the speaker go" and "where should I sit" questions; only which point is
/// held fixed differs.
class FlatnessGrid {
  const FlatnessGrid({
    required this.cols,
    required this.rows,
    required this.values,
    required this.min,
    required this.max,
  });

  /// Grid over the floor plan: col 0..cols-1 spans x = 0..L, row 0..rows-1
  /// spans y = 0..W. Values are dB standard deviations (lower = flatter).
  final int cols;
  final int rows;
  final Float64List values; // row-major, length cols*rows
  final double min;
  final double max;

  double valueAt(int col, int row) => values[row * cols + col];

  /// Normalizes a cell to 0 (flattest found) .. 1 (roughest found).
  double normalizedAt(int col, int row) {
    final span = max - min;
    if (span <= 0) return 0;
    return (valueAt(col, row) - min) / span;
  }
}

/// Arguments bundle so the sweep can run in a background isolate via
/// `compute` (which takes a single message argument).
class AdvisorRequest {
  const AdvisorRequest({
    required this.room,
    required this.modes,
    required this.fixed,
    required this.movingHeightFraction,
    required this.maxHz,
    this.cols = 30,
    this.freqPoints = 96,
  });

  final Room room;
  final List<RoomMode> modes;

  /// The endpoint that does not move (the listener when advising speaker
  /// spots, the speaker when advising listening spots).
  final PlacementPoint fixed;

  /// Height (fraction of room height) at which candidate positions sweep.
  final double movingHeightFraction;

  final double maxHz;
  final int cols;
  final int freqPoints;
}

/// Sweeps candidate positions across the floor plan and scores each by the
/// flatness (dB standard deviation) of the predicted response between it
/// and [AdvisorRequest.fixed]. Top-level so it can be handed to `compute`.
FlatnessGrid computeFlatnessGrid(AdvisorRequest req) {
  final room = req.room;
  final modes = req.modes;
  final cols = req.cols;
  final rows = (cols * room.width / room.length).round().clamp(4, cols);

  final values = Float64List(cols * rows);
  var min = double.infinity;
  var max = -double.infinity;

  for (var row = 0; row < rows; row++) {
    final fy = (row + 0.5) / rows;
    for (var col = 0; col < cols; col++) {
      final fx = (col + 0.5) / cols;
      final moving = PlacementPoint(
        fx: fx,
        fy: fy,
        fz: req.movingHeightFraction,
      );
      final curve = computeRoomResponse(
        modes,
        room,
        moving,
        req.fixed,
        maxHz: req.maxHz,
        points: req.freqPoints,
      );
      final v = curve.flatness;
      values[row * cols + col] = v;
      if (v < min) min = v;
      if (v > max) max = v;
    }
  }

  return FlatnessGrid(
    cols: cols,
    rows: rows,
    values: values,
    min: min.isFinite ? min : 0,
    max: max.isFinite ? max : 0,
  );
}

/// The flattest cell of [grid] as a placement (at [heightFraction]) —
/// used to badge the "best spot" on the heatmap.
PlacementPoint bestSpot(FlatnessGrid grid, double heightFraction) {
  var bestCol = 0, bestRow = 0;
  var best = double.infinity;
  for (var row = 0; row < grid.rows; row++) {
    for (var col = 0; col < grid.cols; col++) {
      final v = grid.valueAt(col, row);
      if (v < best) {
        best = v;
        bestCol = col;
        bestRow = row;
      }
    }
  }
  return PlacementPoint(
    fx: (bestCol + 0.5) / grid.cols,
    fy: (bestRow + 0.5) / grid.rows,
    fz: heightFraction,
  );
}

/// Re-exported here so UI code sizing markers against nodal planes can ask
/// "is this point near a null of the selected mode" without importing the
/// pressure-field module separately.
double modePressureAt(
  RoomMode mode,
  Room room,
  PlacementPoint point,
) =>
    pressureAt(mode, room, x: point.x(room), y: point.y(room), z: point.z(room));
