#pragma once
#include <vector>
#include <cmath>
#include "laplacian.h"
#include "linalg.h"

// Solves (A + shift*I) x = b via Conjugate Gradient, mirroring
// lib/core/numeric/cg_solver.dart. Returns the iteration count.
inline int conjugateGradient(const NeumannLaplacian& a, const std::vector<double>& b,
                              std::vector<double>& x, double shift = 0.0,
                              double tol = 1e-9, int maxIter = 5000) {
    int n = a.cellCount;
    x.assign(n, 0.0);
    std::vector<double> r = b, p = b, ap(n);

    double rsOld = dotv(r, r);
    double bNorm = std::sqrt(dotv(b, b));
    if (bNorm == 0.0) return 0;
    double threshold = tol * tol * bNorm * bNorm;

    int iter = 0;
    while (iter < maxIter && rsOld > threshold) {
        a.apply(p, ap, shift);
        double pap = dotv(p, ap);
        if (pap <= 0) break;
        double alpha = rsOld / pap;
        for (int i = 0; i < n; ++i) x[i] += alpha * p[i];
        for (int i = 0; i < n; ++i) r[i] -= alpha * ap[i];
        double rsNew = dotv(r, r);
        double beta = rsNew / rsOld;
        for (int i = 0; i < n; ++i) p[i] = r[i] + beta * p[i];
        rsOld = rsNew;
        iter++;
    }
    return iter;
}
