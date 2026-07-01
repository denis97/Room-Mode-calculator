#pragma once
#include <vector>
#include <numeric>
#include <cmath>
#include <cstdint>
#include <Eigen/Sparse>

// The Neumann Laplacian (finite-volume or FEM) always has one trivial
// "constant pressure" null vector per *connected component* of the domain --
// not just one globally. A single global mean-subtraction (the natural first
// guess) silently assumes exactly one component; if the domain is actually
// split into several pieces (e.g. a voxelized room whose thin connecting neck
// vanished at low resolution), that assumption is wrong and produces spurious
// near-zero "modes" for every extra component. This file finds the real
// number of components and builds one deflation vector per component.

class UnionFind {
public:
    explicit UnionFind(int n) : parent(n), rank_(n, 0) {
        std::iota(parent.begin(), parent.end(), 0);
    }
    int find(int x) {
        while (parent[x] != x) {
            parent[x] = parent[parent[x]];
            x = parent[x];
        }
        return x;
    }
    void unite(int a, int b) {
        a = find(a); b = find(b);
        if (a == b) return;
        if (rank_[a] < rank_[b]) std::swap(a, b);
        parent[b] = a;
        if (rank_[a] == rank_[b]) rank_[a]++;
    }

private:
    std::vector<int> parent;
    std::vector<int> rank_;
};

inline std::vector<std::vector<int>> componentsFromUnionFind(int n, UnionFind& uf) {
    std::vector<int> compIndex(n, -1);
    std::vector<std::vector<int>> comps;
    for (int i = 0; i < n; ++i) {
        int r = uf.find(i);
        if (compIndex[r] < 0) {
            compIndex[r] = (int)comps.size();
            comps.push_back({});
        }
        comps[compIndex[r]].push_back(i);
    }
    return comps;
}

// Connected components from the FDM neighbour array (6 per cell, -1 = wall).
inline std::vector<std::vector<int>> componentsFromNeighbors(
    int n, const std::vector<int32_t>& neighbors) {
    UnionFind uf(n);
    for (int i = 0; i < n; ++i)
        for (int d = 0; d < 6; ++d) {
            int32_t nb = neighbors[i * 6 + d];
            if (nb >= 0) uf.unite(i, (int)nb);
        }
    return componentsFromUnionFind(n, uf);
}

// Connected components from a sparse matrix's off-diagonal sparsity pattern
// (FEM: two nodes are connected if they share a nonzero K entry, i.e. share a
// tet).
inline std::vector<std::vector<int>> componentsFromSparsity(const Eigen::SparseMatrix<double>& K) {
    int n = (int)K.rows();
    UnionFind uf(n);
    for (int col = 0; col < K.outerSize(); ++col)
        for (Eigen::SparseMatrix<double>::InnerIterator it(K, col); it; ++it)
            if (it.row() != it.col()) uf.unite((int)it.row(), (int)it.col());
    return componentsFromUnionFind(n, uf);
}

// One normalized null vector per component. [weight] is the per-DOF scaling
// of the constant mode (pass nullptr for uniform weight -- the FDM case,
// whose implicit mass is a multiple of identity; pass sqrt(mass_i) for FEM's
// M^{1/2}-transformed operator).
inline std::vector<std::vector<double>> buildNullVectors(
    int n, const std::vector<std::vector<int>>& components, const std::vector<double>* weight) {
    std::vector<std::vector<double>> nullVecs;
    for (auto& comp : components) {
        std::vector<double> v(n, 0.0);
        double normSq = 0.0;
        for (int idx : comp) {
            double w = weight ? (*weight)[idx] : 1.0;
            v[idx] = w;
            normSq += w * w;
        }
        double norm = std::sqrt(normSq);
        if (norm > 0) for (int idx : comp) v[idx] /= norm;
        nullVecs.push_back(std::move(v));
    }
    return nullVecs;
}

// Projects v onto the subspace orthogonal to every vector in nullVecs.
inline void deflateAll(std::vector<double>& v, const std::vector<std::vector<double>>& nullVecs) {
    for (auto& nv : nullVecs) {
        double dot = 0.0;
        for (size_t i = 0; i < v.size(); ++i) dot += v[i] * nv[i];
        for (size_t i = 0; i < v.size(); ++i) v[i] -= dot * nv[i];
    }
}
