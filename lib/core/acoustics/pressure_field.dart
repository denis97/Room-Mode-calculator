import 'dart:math' as math;

import 'mode.dart';
import 'room.dart';

/// Sampling of the standing-pressure field of a single room mode.
///
/// For a rigid-wall box the (normalized) sound pressure of mode (p, q, r) is
///
///     P(x,y,z) = cos(pπx/L) · cos(qπy/W) · cos(rπz/H)
///
/// ranging in [-1, 1]. Antinodes (|P| = 1) sit at the walls; nodal lines
/// (P = 0) are where any cosine term crosses zero. This is the data behind the
/// 2D pressure heatmap.

/// Signed pressure at a point. Coordinates are in metres within the room.
double pressureAt(
  RoomMode mode,
  Room room, {
  required double x,
  required double y,
  required double z,
}) {
  return math.cos(mode.p * math.pi * x / room.length) *
      math.cos(mode.q * math.pi * y / room.width) *
      math.cos(mode.r * math.pi * z / room.height);
}

/// A regular grid of signed pressure values over a horizontal slice (constant
/// height [z]) of the room, with [cols] samples along the length (x) and [rows]
/// along the width (y). Values are in [-1, 1]; row 0 is y = 0.
class PressureGrid {
  PressureGrid({
    required this.cols,
    required this.rows,
    required this.values,
  });

  final int cols;
  final int rows;
  final List<double> values; // length == cols * rows, row-major

  double valueAt(int col, int row) => values[row * cols + col];
}

/// Samples [mode]'s pressure over a horizontal plane at height [z] (defaults to
/// the room centre height). The grid is sized [cols] × [rows].
PressureGrid samplePressureSlice(
  RoomMode mode,
  Room room, {
  double? z,
  int cols = 64,
  int rows = 64,
}) {
  final sliceZ = z ?? room.height / 2;
  final values = List<double>.filled(cols * rows, 0);
  for (var row = 0; row < rows; row++) {
    // Sample at cell centres so the field is symmetric across the slice.
    final y = (row + 0.5) / rows * room.width;
    for (var col = 0; col < cols; col++) {
      final x = (col + 0.5) / cols * room.length;
      values[row * cols + col] =
          pressureAt(mode, room, x: x, y: y, z: sliceZ);
    }
  }
  return PressureGrid(cols: cols, rows: rows, values: values);
}
