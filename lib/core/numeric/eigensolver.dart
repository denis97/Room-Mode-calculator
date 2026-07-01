import 'dart:math' as math;
import 'dart:typed_data';

import 'cg_solver.dart';
import 'laplacian_operator.dart';
import 'linalg.dart';

/// One computed eigenpair: the eigenvalue `μ = k²` and its (unit-norm,
/// zero-mean) eigenvector over the grid's inside cells.
class EigenPair {
  EigenPair(this.eigenvalue, this.vector);
  final double eigenvalue;
  final Float64List vector;
}

/// Computes the [count] smallest **non-zero** eigenpairs of the Neumann
/// Laplacian via inverse iteration with deflation.
///
/// Each pair is found by repeatedly solving `A w = v` (CG), which amplifies the
/// smallest remaining eigenvalue; the constant null space is removed by keeping
/// vectors zero-mean and already-found eigenvectors are deflated out, so the
/// iteration lands on the next mode up. Deterministic for a given [seed].
List<EigenPair> smallestEigenpairs(
  NeumannLaplacian a,
  int count, {
  int seed = 1,
  double tol = 1e-7,
  int maxIterations = 400,
  double cgTol = 1e-9,
  double shift = 1e-7,
}) {
  final n = a.size;
  final rng = math.Random(seed);
  final found = <EigenPair>[];
  final scratch = Float64List(n);
  final w = Float64List(n);

  void deflate(Float64List x) {
    subtractMean(x);
    for (final pair in found) {
      axpy(-dot(x, pair.vector), pair.vector, x);
    }
  }

  for (var m = 0; m < count && m < n - 1; m++) {
    var v = randomZeroMean(n, rng);
    deflate(v);
    normalize(v);
    var lambda = a.rayleighQuotient(v, scratch);

    for (var iter = 0; iter < maxIterations; iter++) {
      conjugateGradient(a, v, w, shift: shift, tol: cgTol);
      deflate(w);
      if (norm(w) == 0) break;
      normalize(w);

      final newLambda = a.rayleighQuotient(w, scratch);

      // Residual ‖A w − λ w‖ measures how close w is to a true eigenvector.
      a.apply(w, scratch);
      var residual = 0.0;
      for (var i = 0; i < n; i++) {
        final e = scratch[i] - newLambda * w[i];
        residual += e * e;
      }
      residual = math.sqrt(residual);

      copyInto(w, v);
      final converged = residual <= tol * math.max(newLambda, 1e-12) ||
          (lambda - newLambda).abs() <= tol * math.max(newLambda, 1e-12);
      lambda = newLambda;
      if (converged) break;
    }

    found.add(EigenPair(lambda, Float64List.fromList(v)));
  }

  found.sort((x, y) => x.eigenvalue.compareTo(y.eigenvalue));
  return found;
}
