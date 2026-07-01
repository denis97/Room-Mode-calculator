import 'dart:math' as math;
import 'dart:typed_data';

import '../acoustics/speed_of_sound.dart';
import '../constants.dart';
import '../geometry/room_shape.dart';
import '../geometry/voxel_grid.dart';
import 'eigensolver.dart';
import 'laplacian_operator.dart';

/// A numerically-computed room mode for an arbitrary shape: its resonant
/// [frequency] (Hz) and the pressure [field] sampled over the grid's inside
/// cells (unit-norm, signed). Unlike the analytical cuboid modes there are no
/// (p, q, r) indices, because they are only meaningful for a box.
class ComputedMode {
  ComputedMode({
    required this.frequency,
    required this.eigenvalue,
    required this.field,
  });

  final double frequency;
  final double eigenvalue;
  final Float64List field;
}

/// The result of a numerical modal analysis: the [grid] the modes live on and
/// the list of [modes] (ascending in frequency).
class ModalAnalysisResult {
  ModalAnalysisResult({required this.grid, required this.modes});

  final VoxelGrid grid;
  final List<ComputedMode> modes;
}

/// A horizontal cross-section of a mode's pressure field at a fixed height.
/// [values] is row-major (`nx` × `ny`); a cell is `null` where it lies outside
/// the room. Values are signed; [maxAbs] is the field's peak magnitude for
/// color normalization.
class ModeSlice {
  ModeSlice({
    required this.nx,
    required this.ny,
    required this.values,
    required this.maxAbs,
  });

  final int nx;
  final int ny;
  final List<double?> values;
  final double maxAbs;

  double? at(int i, int j) => values[j * nx + i];
}

/// Extracts the horizontal slice of [field] (over [grid]) nearest to height
/// [zMetres] — the interior cross-section behind the 2D slice view.
ModeSlice horizontalSlice(VoxelGrid grid, Float64List field, double zMetres) {
  final k = (((zMetres - grid.originZ) / grid.h).floor())
      .clamp(0, grid.nz - 1);
  final values = List<double?>.filled(grid.nx * grid.ny, null);
  var maxAbs = 1e-12;
  for (final v in field) {
    final a = v.abs();
    if (a > maxAbs) maxAbs = a;
  }
  for (var c = 0; c < grid.cellCount; c++) {
    if (grid.ck[c] == k) {
      values[grid.cj[c] * grid.nx + grid.ci[c]] = field[c];
    }
  }
  return ModeSlice(nx: grid.nx, ny: grid.ny, values: values, maxAbs: maxAbs);
}

/// Computes the lowest [modeCount] acoustic modes of an arbitrary [shape] by
/// solving the rigid-wall Helmholtz eigenproblem on a voxel grid.
///
/// For a [BoxShape] this reproduces the analytical cuboid frequencies (within
/// the grid's discretization error), which is how the solver is validated;
/// for non-rectangular shapes it is the only way to get the modes.
///
/// [targetPerAxis] sets the grid resolution (cells along the longest axis):
/// higher is more accurate but quadratically-to-cubically slower.
ModalAnalysisResult analyzeRoomShape(
  RoomShape shape, {
  double temperatureC = AcousticDefaults.temperatureC,
  int targetPerAxis = 16,
  int modeCount = 8,
}) {
  final grid = VoxelGrid.fromShape(shape, targetPerAxis: targetPerAxis);
  final operator = NeumannLaplacian(grid);
  final pairs = smallestEigenpairs(operator, modeCount);

  final c = speedOfSound(temperatureC: temperatureC);
  final modes = pairs.map((pair) {
    final mu = math.max(pair.eigenvalue, 0.0);
    // μ = k² = (2πf/c)²  ⇒  f = c·√μ / (2π)
    final frequency = c * math.sqrt(mu) / (2 * math.pi);
    return ComputedMode(
      frequency: frequency,
      eigenvalue: mu,
      field: pair.vector,
    );
  }).toList();

  return ModalAnalysisResult(grid: grid, modes: modes);
}
