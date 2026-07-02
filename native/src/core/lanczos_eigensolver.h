#pragma once
#include <vector>
#include <algorithm>
#include <random>
#include <Eigen/Dense>
#include "laplacian.h"
#include "cg.h"
#include "linalg.h"
#include "null_space.h"

// Finds the smallest non-trivial eigenpairs of the Neumann Laplacian via
// shift-invert Lanczos: run Lanczos on OP = (A + shift*I)^-1 (computed by
// CG), whose *largest* eigenvalues correspond to A's *smallest* eigenvalues.
//
// The domain's connected components are detected up front (componentsFrom-
// Neighbors) and *all* of their constant-pressure null vectors are deflated
// at every step -- not just a single global mean. A voxelized non-convex room
// can disconnect into separate pieces at low resolution (e.g. a thin
// connecting neck vanishing), and each extra piece has its own trivial
// eigenvalue; deflating only the global mean lets those leak through as
// spurious near-zero "modes".

struct EigenPair {
    double eigenvalue; // mu = k^2 of A
    std::vector<double> vector;
};

inline std::vector<EigenPair> lanczosSmallestEigenpairs(
    const NeumannLaplacian& a, int count, int subspaceSize,
    double shift = 1e-7, double cgTol = 1e-9, unsigned seed = 1) {
    int n = a.cellCount;

    auto components = componentsFromNeighbors(n, a.neighbors);
    auto nullVecs = buildNullVectors(n, components, nullptr);

    int m = std::min(subspaceSize, n - (int)nullVecs.size());
    std::vector<std::vector<double>> V(m, std::vector<double>(n));
    std::vector<double> alpha(m, 0.0), beta(m, 0.0);

    std::mt19937 rng(seed);
    std::uniform_real_distribution<double> dist(-1.0, 1.0);
    std::vector<double> v(n);
    for (int i = 0; i < n; ++i) v[i] = dist(rng);
    deflateAll(v, nullVecs);
    normalizev(v);
    V[0] = v;

    std::vector<double> w(n), cgOut(n);

    for (int j = 0; j < m; ++j) {
        conjugateGradient(a, V[j], cgOut, shift, cgTol);
        w = cgOut;
        deflateAll(w, nullVecs);

        alpha[j] = dotv(w, V[j]);
        for (int i = 0; i < n; ++i) w[i] -= alpha[j] * V[j][i];
        if (j > 0) for (int i = 0; i < n; ++i) w[i] -= beta[j] * V[j - 1][i];

        for (int pass = 0; pass < 2; ++pass) {
            for (int i = 0; i <= j; ++i) {
                double c = dotv(w, V[i]);
                for (int k = 0; k < n; ++k) w[k] -= c * V[i][k];
            }
        }
        deflateAll(w, nullVecs);

        double b = normv(w);
        if (j + 1 < m) {
            beta[j + 1] = b;
            if (b < 1e-12) { m = j + 1; break; }
            for (int i = 0; i < n; ++i) V[j + 1][i] = w[i] / b;
        }
    }

    Eigen::MatrixXd T = Eigen::MatrixXd::Zero(m, m);
    for (int i = 0; i < m; ++i) T(i, i) = alpha[i];
    for (int i = 1; i < m; ++i) { T(i, i - 1) = beta[i]; T(i - 1, i) = beta[i]; }
    Eigen::SelfAdjointEigenSolver<Eigen::MatrixXd> es(T);
    Eigen::VectorXd theta = es.eigenvalues();
    Eigen::MatrixXd Y = es.eigenvectors();

    std::vector<EigenPair> result;
    for (int idx = m - 1; idx >= 0 && (int)result.size() < count; --idx) {
        double th = theta(idx);
        if (th <= 0) continue;
        double mu = 1.0 / th - shift;
        std::vector<double> vec(n, 0.0);
        for (int i = 0; i < m; ++i) {
            double yi = Y(i, idx);
            for (int k = 0; k < n; ++k) vec[k] += yi * V[i][k];
        }
        normalizev(vec);
        result.push_back({std::max(mu, 0.0), vec});
    }
    std::sort(result.begin(), result.end(),
              [](const EigenPair& x, const EigenPair& y) { return x.eigenvalue < y.eigenvalue; });
    return result;
}
