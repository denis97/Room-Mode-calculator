import 'dart:typed_data';

import 'laplacian_operator.dart';
import 'linalg.dart';

/// Solves `(A + shift·I) x = b` for the symmetric positive (semi-)definite
/// Neumann Laplacian using the Conjugate Gradient method.
///
/// `b` must be zero-mean (orthogonal to the constant null space); because `A`
/// preserves the zero-mean subspace, the solution stays zero-mean too. A tiny
/// positive [shift] keeps the system strictly positive definite for robustness.
/// Returns the number of iterations performed; [x] holds the solution.
int conjugateGradient(
  NeumannLaplacian a,
  Float64List b,
  Float64List x, {
  double shift = 0,
  double tol = 1e-9,
  int maxIter = 5000,
}) {
  final n = a.size;
  for (var i = 0; i < n; i++) {
    x[i] = 0;
  }

  final r = Float64List.fromList(b); // r = b - A·0 = b
  final p = Float64List.fromList(b);
  final ap = Float64List(n);

  var rsOld = dot(r, r);
  final bNorm = norm(b);
  if (bNorm == 0) return 0;
  final threshold = tol * tol * bNorm * bNorm;

  var iter = 0;
  while (iter < maxIter && rsOld > threshold) {
    a.apply(p, ap, shift: shift);
    final pap = dot(p, ap);
    if (pap <= 0) break; // numerical safety
    final alpha = rsOld / pap;
    axpy(alpha, p, x);
    axpy(-alpha, ap, r);
    final rsNew = dot(r, r);
    final beta = rsNew / rsOld;
    for (var i = 0; i < n; i++) {
      p[i] = r[i] + beta * p[i];
    }
    rsOld = rsNew;
    iter++;
  }
  return iter;
}
