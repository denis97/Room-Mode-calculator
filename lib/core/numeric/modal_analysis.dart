import 'dart:math' as math;
import 'dart:typed_data';

import '../acoustics/speed_of_sound.dart';
import '../constants.dart';
import '../geometry/render_mesh.dart';
import '../geometry/room_shape.dart';
import '../geometry/voxel_grid.dart';
import 'eigensolver.dart';
import 'laplacian_operator.dart';

/// A numerically-computed room mode for an arbitrary shape: its resonant
/// [frequency] (Hz) and the pressure [field] sampled at each node of the
/// result's [ModalAnalysisResult.mesh] (unit-norm, signed). Unlike the
/// analytical cuboid modes there are no (p, q, r) indices, because they are
/// only meaningful for a box.
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

/// Which solver actually produced a [ModalAnalysisResult]: the native FEM
/// path (native/, the accurate one) or the pure-Dart FDM path (a fallback --
/// see [runFloorPlanAnalysis] in custom_room_providers.dart for when that
/// happens and why it's never silent).
enum SolverBackend { nativeFem, dartFdm }

/// The result of a numerical modal analysis: the boundary surface [mesh] the
/// modes' fields live on, the list of [modes] (ascending in frequency), and
/// which [backend] actually solved it.
class ModalAnalysisResult {
  ModalAnalysisResult({
    required this.mesh,
    required this.modes,
    required this.backend,
  });

  final RenderMesh mesh;
  final List<ComputedMode> modes;
  final SolverBackend backend;
}

/// Converts a solved [VoxelGrid] field (one value per interior cell) into a
/// boundary [RenderMesh] plus matching per-node field values -- the Dart FDM
/// fallback's equivalent of the native FEM solver's own mesh boundary.
/// Each boundary quad's four corners are *not* shared with neighbouring
/// quads (flat-shaded: every corner gets that quad's single cell value),
/// unlike the FEM path where field values are genuinely smooth per-node.
class _VoxelBoundary {
  _VoxelBoundary(this.mesh, this.sourceCell);
  final RenderMesh mesh;

  /// For each mesh node, the voxel-grid cell index whose field value it uses.
  final Int32List sourceCell;
}

_VoxelBoundary _voxelBoundaryMesh(VoxelGrid grid) {
  final h = grid.h;
  final positions = <double>[];
  final triangles = <int>[];
  final sourceCell = <int>[];

  void addQuad(int cell, List<(double, double, double)> corners) {
    final base = positions.length ~/ 3;
    for (final (x, y, z) in corners) {
      positions.addAll([x, y, z]);
      sourceCell.add(cell);
    }
    triangles.addAll(
        [base, base + 1, base + 2, base, base + 2, base + 3]);
  }

  for (var c = 0; c < grid.cellCount; c++) {
    final i = grid.ci[c], j = grid.cj[c], k = grid.ck[c];
    final x0 = grid.originX + i * h, x1 = x0 + h;
    final y0 = grid.originY + j * h, y1 = y0 + h;
    final z0 = grid.originZ + k * h, z1 = z0 + h;
    final base = c * 6;
    if (grid.neighbors[base + 0] < 0) {
      addQuad(c, [(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)]);
    }
    if (grid.neighbors[base + 1] < 0) {
      addQuad(c, [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)]);
    }
    if (grid.neighbors[base + 2] < 0) {
      addQuad(c, [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)]);
    }
    if (grid.neighbors[base + 3] < 0) {
      addQuad(c, [(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]);
    }
    if (grid.neighbors[base + 4] < 0) {
      addQuad(c, [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)]);
    }
    if (grid.neighbors[base + 5] < 0) {
      addQuad(c, [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]);
    }
  }

  return _VoxelBoundary(
    RenderMesh(
      positions: Float64List.fromList(positions),
      triangles: Int32List.fromList(triangles),
    ),
    Int32List.fromList(sourceCell),
  );
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
  final boundary = _voxelBoundaryMesh(grid);

  final c = speedOfSound(temperatureC: temperatureC);
  final modes = pairs.map((pair) {
    final mu = math.max(pair.eigenvalue, 0.0);
    // μ = k² = (2πf/c)²  ⇒  f = c·√μ / (2π)
    final frequency = c * math.sqrt(mu) / (2 * math.pi);
    final field = Float64List(boundary.sourceCell.length);
    for (var i = 0; i < field.length; i++) {
      field[i] = pair.vector[boundary.sourceCell[i]];
    }
    return ComputedMode(frequency: frequency, eigenvalue: mu, field: field);
  }).toList();

  return ModalAnalysisResult(
    mesh: boundary.mesh,
    modes: modes,
    backend: SolverBackend.dartFdm,
  );
}
