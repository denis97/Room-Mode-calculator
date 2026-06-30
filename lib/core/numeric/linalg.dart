import 'dart:math' as math;
import 'dart:typed_data';

/// Small dense vector helpers used by the iterative solvers. Vectors are
/// [Float64List]s of equal length; operations are deliberately allocation-light.

double dot(Float64List a, Float64List b) {
  var s = 0.0;
  for (var i = 0; i < a.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

double norm(Float64List a) => math.sqrt(dot(a, a));

/// y += alpha * x
void axpy(double alpha, Float64List x, Float64List y) {
  for (var i = 0; i < x.length; i++) {
    y[i] += alpha * x[i];
  }
}

void scale(Float64List x, double alpha) {
  for (var i = 0; i < x.length; i++) {
    x[i] *= alpha;
  }
}

void copyInto(Float64List src, Float64List dst) {
  dst.setRange(0, src.length, src);
}

/// Removes the mean, projecting onto the subspace orthogonal to the constant
/// vector (the Neumann Laplacian's null space).
void subtractMean(Float64List x) {
  var mean = 0.0;
  for (var i = 0; i < x.length; i++) {
    mean += x[i];
  }
  mean /= x.length;
  for (var i = 0; i < x.length; i++) {
    x[i] -= mean;
  }
}

void normalize(Float64List x) {
  final n = norm(x);
  if (n > 0) scale(x, 1 / n);
}

/// A zero-mean, unit-norm random vector — a starting guess for iteration.
Float64List randomZeroMean(int n, math.Random rng) {
  final v = Float64List(n);
  for (var i = 0; i < n; i++) {
    v[i] = rng.nextDouble() * 2 - 1;
  }
  subtractMean(v);
  normalize(v);
  return v;
}
