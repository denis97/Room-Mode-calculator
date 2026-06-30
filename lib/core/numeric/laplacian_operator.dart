import 'dart:typed_data';

import '../geometry/voxel_grid.dart';

/// The discrete negative Laplacian operator `A = -∇²` on a [VoxelGrid] with
/// Neumann (rigid-wall, zero normal velocity) boundary conditions.
///
/// Using a cell-centred finite-volume stencil, each interior face contributes
/// `(u_self − u_neighbour) / h²`; faces on a wall (no in-domain neighbour)
/// contribute nothing, which *is* the rigid-wall condition. The operator is
/// symmetric positive semi-definite; its null space is the constant vector
/// (the trivial "DC" mode at 0 Hz), and `A·u` always has zero sum, so the
/// iterates of CG started from zero stay orthogonal to that null space.
///
/// Eigenvalues of `A` are `μ = k² = (2πf/c)²`, so `f = c·√μ / (2π)`.
class NeumannLaplacian {
  NeumannLaplacian(this.grid) : _invH2 = 1.0 / (grid.h * grid.h);

  final VoxelGrid grid;
  final double _invH2;

  int get size => grid.cellCount;

  /// Computes `y = A·x` (optionally `y = (A + shift·I)·x`). [x] and [y] are
  /// indexed by compact cell index and must have length [size].
  void apply(Float64List x, Float64List y, {double shift = 0}) {
    final neighbors = grid.neighbors;
    for (var c = 0; c < grid.cellCount; c++) {
      final base = c * 6;
      var degree = 0;
      var neighborSum = 0.0;
      for (var d = 0; d < 6; d++) {
        final nb = neighbors[base + d];
        if (nb >= 0) {
          degree++;
          neighborSum += x[nb];
        }
      }
      y[c] = _invH2 * (degree * x[c] - neighborSum) + shift * x[c];
    }
  }

  /// Rayleigh quotient `(xᵀ A x) / (xᵀ x)` — the eigenvalue estimate for [x].
  double rayleighQuotient(Float64List x, Float64List scratch) {
    apply(x, scratch);
    var num = 0.0;
    var den = 0.0;
    for (var i = 0; i < x.length; i++) {
      num += x[i] * scratch[i];
      den += x[i] * x[i];
    }
    return den == 0 ? 0 : num / den;
  }
}
