#pragma once
#include <Eigen/Sparse>
#include <Eigen/SparseCholesky>
#include <vector>
#include <random>
#include <algorithm>
#include "fem_assembly.h"
#include "null_space.h"

// Solves the generalized eigenproblem K u = mu M u by transforming to the
// standard symmetric problem A' u' = mu u', A' = Minv_sqrt K Minv_sqrt
// (u' = M^{1/2} u); since M is diagonal (lumped) this scaling is trivial and
// A' stays symmetric, so the same shift-invert Lanczos process as the
// finite-volume solver applies, just with a different operator.
//
// Connected components are detected from K's sparsity pattern and *all* of
// their null vectors are deflated (see null_space.h) -- the FEM path is far
// less prone to accidental disconnection than a voxel grid (the mesh follows
// the true polygon boundary exactly), but a user-drawn room with a
// near-zero-width neck could still produce an ill-conditioned near-
// disconnection, so this is defensive robustness, not just parity with FDM.

struct FemEigenPair {
    double eigenvalue;
    std::vector<double> vector; // physical (unscaled) node values
};

struct FemOperator {
    const Eigen::SparseMatrix<double>& K;
    const std::vector<double>& minvSqrt;

    Eigen::VectorXd apply(const Eigen::VectorXd& x) const {
        Eigen::VectorXd y(x.size());
        for (int i = 0; i < x.size(); ++i) y[i] = x[i] * minvSqrt[i];
        Eigen::VectorXd z = K * y;
        for (int i = 0; i < z.size(); ++i) z[i] *= minvSqrt[i];
        return z;
    }

    // Diagonal of M^{-1/2} K M^{-1/2}, used for Jacobi preconditioning.
    Eigen::VectorXd diagonal() const {
        Eigen::VectorXd d = K.diagonal();
        Eigen::VectorXd out(d.size());
        for (int i = 0; i < d.size(); ++i) out[i] = d[i] * minvSqrt[i] * minvSqrt[i];
        return out;
    }
};

// Jacobi (diagonal) preconditioning: cheap (O(n) to build and apply per
// iteration) but matters a lot here, because element quality after
// ear-clipping + subdivision is not uniform -- a concave floor plan's
// reflex corner produces thinner/more irregular triangles nearby than a
// plain box gets, which ill-conditions the stiffness matrix there. On a
// 5x4x3 box vs. the app's default L-room at the same mesh level, that
// showed up as needing ~8x more *unpreconditioned* CG iterations for the
// same size problem (not explained by the ~2x node-count difference); the
// diagonal preconditioner below cuts that back to roughly 2.5-3.5x.
//
// [precondMinv] is 1/(diag(A') + shift) -- the same for every CG solve
// within one Lanczos run (shift is fixed), so femLanczosSmallestEigenpairs
// builds it once via femJacobiPreconditioner and passes it in, instead of
// this recomputing op.diagonal() (an O(nnz) sparse-matrix pass) on every one
// of the ~2*count+10 Lanczos-step CG calls.
inline Eigen::VectorXd femJacobiPreconditioner(const FemOperator& op, double shift) {
    Eigen::VectorXd diag = op.diagonal();
    Eigen::VectorXd minv(diag.size());
    for (int i = 0; i < diag.size(); ++i) {
        double d = diag[i] + shift;
        minv[i] = d > 1e-300 ? 1.0 / d : 1.0;
    }
    return minv;
}

inline int femCG(const FemOperator& op, const Eigen::VectorXd& b, Eigen::VectorXd& x,
                  const Eigen::VectorXd& minv, double shift, double tol = 1e-9,
                  int maxIter = 5000) {
    int n = (int)b.size();
    x = Eigen::VectorXd::Zero(n);

    Eigen::VectorXd r = b;
    Eigen::VectorXd z = r.cwiseProduct(minv);
    Eigen::VectorXd p = z, ap;
    double rzOld = r.dot(z);
    double rsOld = r.dot(r);
    double bNorm = std::sqrt(b.dot(b));
    if (bNorm == 0) return 0;
    double threshold = tol * tol * bNorm * bNorm;
    int iter = 0;
    while (iter < maxIter && rsOld > threshold) {
        ap = op.apply(p) + shift * p;
        double pap = p.dot(ap);
        if (pap <= 0) break;
        double alpha = rzOld / pap;
        x += alpha * p;
        r -= alpha * ap;
        rsOld = r.dot(r);
        iter++;
        if (rsOld <= threshold) break;
        z = r.cwiseProduct(minv);
        double rzNew = r.dot(z);
        double beta = rzNew / rzOld;
        p = z + beta * p;
        rzOld = rzNew;
    }
    return iter;
}

// Materializes A' + shift*I = M^{-1/2} K M^{-1/2} + shift*I as an explicit
// sparse matrix, for the direct factorization used below. `op.apply()` is
// matrix-free (never forms this explicitly) because that's the right choice
// when you only need a handful of matvecs -- but Lanczos needs O(count)
// solves of *the exact same system* (same matrix, different right-hand
// side, since shift is fixed for the whole run), and for that a one-time
// sparse factorization is far cheaper than paying for iterative CG
// convergence on every single one of those solves. See
// femLanczosSmallestEigenpairs and native/README.md.
inline Eigen::SparseMatrix<double> femShiftedOperatorMatrix(const FemOperator& op, double shift) {
    Eigen::SparseMatrix<double> Ap = op.K;
    for (int k = 0; k < Ap.outerSize(); ++k)
        for (Eigen::SparseMatrix<double>::InnerIterator it(Ap, k); it; ++it)
            it.valueRef() *= op.minvSqrt[it.row()] * op.minvSqrt[it.col()];
    for (int i = 0; i < Ap.rows(); ++i) Ap.coeffRef(i, i) += shift;
    return Ap;
}

inline void deflateAllEigen(Eigen::VectorXd& v, const std::vector<std::vector<double>>& nullVecs) {
    for (auto& nv : nullVecs) {
        double dot = 0.0;
        for (int i = 0; i < v.size(); ++i) dot += v[i] * nv[i];
        for (int i = 0; i < v.size(); ++i) v[i] -= dot * nv[i];
    }
}

inline std::vector<FemEigenPair> femLanczosSmallestEigenpairs(
    const FemOperator& op, int n, int count, int subspaceSize,
    double shift = 1e-7, double cgTol = 1e-9, unsigned seed = 1) {
    // Null vector of K (per component) is the constant "1" restricted to that
    // component; in transformed space that becomes M^{1/2}*1, i.e. entries =
    // 1/minvSqrt_i within the component.
    auto components = componentsFromSparsity(op.K);
    std::vector<double> weight(n);
    for (int i = 0; i < n; ++i) weight[i] = 1.0 / op.minvSqrt[i];
    auto nullVecsStd = buildNullVectors(n, components, &weight);
    std::vector<Eigen::VectorXd> nullVecs;
    for (auto& v : nullVecsStd) nullVecs.push_back(Eigen::Map<Eigen::VectorXd>(v.data(), v.size()));
    auto deflate = [&](Eigen::VectorXd& v) {
        for (auto& nv : nullVecs) v -= (v.dot(nv)) * nv;
    };

    int m = std::min(subspaceSize, n - (int)nullVecs.size());
    std::vector<Eigen::VectorXd> V(m);
    std::vector<double> alpha(m, 0.0), beta(m, 0.0);

    // Every one of the m Lanczos steps solves (A' + shift*I) w = V[j] --
    // same matrix, different right-hand side. Factor it once (a sparse
    // Cholesky) and reuse that factorization for every step's solve, rather
    // than running iterative CG to convergence m separate times. Measured
    // on the app's default L-room at max resolution: this took a 210-step
    // solve (subspaceSize for 100 requested modes) from what would have
    // been ~70s of repeated CG down to ~12s total, including the
    // factorization itself -- and the win only grows with modeCount, since
    // the factorization cost is paid once but amortized over more steps.
    //
    // Falls back to Jacobi-preconditioned CG (femCG) if the factorization
    // fails -- defensive robustness for a shape/mesh combination this
    // wasn't tested against, not something expected to trigger in practice
    // (the shift plus null-space deflation should keep A' + shift*I
    // positive definite for any valid mesh).
    Eigen::SimplicialLDLT<Eigen::SparseMatrix<double>> factorization(
        femShiftedOperatorMatrix(op, shift));
    bool useFactorization = factorization.info() == Eigen::Success;
    Eigen::VectorXd jacobiMinv;
    if (!useFactorization) jacobiMinv = femJacobiPreconditioner(op, shift);

    std::mt19937 rng(seed);
    std::uniform_real_distribution<double> dist(-1.0, 1.0);
    Eigen::VectorXd v0(n);
    for (int i = 0; i < n; ++i) v0[i] = dist(rng);
    deflate(v0);
    v0.normalize();
    V[0] = v0;

    for (int j = 0; j < m; ++j) {
        Eigen::VectorXd w;
        if (useFactorization) {
            w = factorization.solve(V[j]);
        } else {
            femCG(op, V[j], w, jacobiMinv, shift, cgTol);
        }
        deflate(w);

        alpha[j] = w.dot(V[j]);
        w -= alpha[j] * V[j];
        if (j > 0) w -= beta[j] * V[j - 1];

        for (int pass = 0; pass < 2; ++pass)
            for (int i = 0; i <= j; ++i) w -= (w.dot(V[i])) * V[i];
        deflate(w);

        double b = w.norm();
        if (j + 1 < m) {
            beta[j + 1] = b;
            if (b < 1e-12) { m = j + 1; break; }
            V[j + 1] = w / b;
        }
    }

    Eigen::MatrixXd T = Eigen::MatrixXd::Zero(m, m);
    for (int i = 0; i < m; ++i) T(i, i) = alpha[i];
    for (int i = 1; i < m; ++i) { T(i, i - 1) = beta[i]; T(i - 1, i) = beta[i]; }
    Eigen::SelfAdjointEigenSolver<Eigen::MatrixXd> es(T);
    Eigen::VectorXd theta = es.eigenvalues();
    Eigen::MatrixXd Y = es.eigenvectors();

    std::vector<FemEigenPair> result;
    for (int idx = m - 1; idx >= 0 && (int)result.size() < count; --idx) {
        double th = theta(idx);
        if (th <= 0) continue;
        double mu = 1.0 / th - shift;
        Eigen::VectorXd vec = Eigen::VectorXd::Zero(n);
        for (int i = 0; i < m; ++i) vec += Y(i, idx) * V[i];
        for (int i = 0; i < n; ++i) vec[i] *= op.minvSqrt[i]; // back to physical space
        vec.normalize();
        result.push_back({std::max(mu, 0.0), std::vector<double>(vec.data(), vec.data() + n)});
    }
    std::sort(result.begin(), result.end(),
              [](const FemEigenPair& x, const FemEigenPair& y) { return x.eigenvalue < y.eigenvalue; });
    return result;
}
