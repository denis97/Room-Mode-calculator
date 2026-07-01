#pragma once
#include <vector>
#include <array>
#include <cmath>
#include <algorithm>
#include "polygon.h"
#include "fem_assembly.h" // Vec3

struct PolyTetMesh {
    std::vector<Vec3> nodes;
    std::vector<std::array<int, 4>> tets;
};

using Tri2D = std::array<std::pair<double, double>, 3>;

// Fan-triangulates a polygon that is star-shaped from its centroid (true of
// any convex polygon, and of a symmetric star polygon).
inline std::vector<Tri2D> fanTriangulate(const Polygon& poly) {
    double cx = 0, cy = 0;
    for (auto& v : poly.verts) { cx += v.first; cy += v.second; }
    cx /= poly.verts.size(); cy /= poly.verts.size();

    std::vector<Tri2D> tris;
    size_t n = poly.verts.size();
    for (size_t i = 0; i < n; ++i)
        tris.push_back({std::make_pair(cx, cy), poly.verts[i], poly.verts[(i + 1) % n]});
    return tris;
}

// Uniform 1-to-4 subdivision (splits each triangle at its edge midpoints).
// Refines resolution while exactly preserving the original polygon boundary.
inline std::vector<Tri2D> subdivide(const std::vector<Tri2D>& tris) {
    auto mid = [](std::pair<double, double> a, std::pair<double, double> b) {
        return std::make_pair((a.first + b.first) / 2, (a.second + b.second) / 2);
    };
    std::vector<Tri2D> out;
    for (auto& t : tris) {
        auto m01 = mid(t[0], t[1]);
        auto m12 = mid(t[1], t[2]);
        auto m20 = mid(t[2], t[0]);
        out.push_back({t[0], m01, m20});
        out.push_back({m01, t[1], m12});
        out.push_back({m20, m12, t[2]});
        out.push_back({m01, m12, m20});
    }
    return out;
}

// Extrudes a 2D triangulation through nz layers of height, splitting each
// triangular prism into 3 tets. Diagonals are chosen from *globally sorted*
// vertex indices (not each triangle's arbitrary local order), so two prisms
// sharing a rectangular face always pick the same diagonal -- required for a
// conforming (crack-free) mesh from an unstructured triangulation.
inline PolyTetMesh extrudeToTets(const std::vector<Tri2D>& tris2d, double height, int nz) {
    PolyTetMesh mesh;
    double dz = height / nz;

    std::vector<std::pair<double, double>> verts2d;
    auto findOrAdd = [&](std::pair<double, double> p) -> int {
        for (size_t i = 0; i < verts2d.size(); ++i) {
            if (std::fabs(verts2d[i].first - p.first) < 1e-9 &&
                std::fabs(verts2d[i].second - p.second) < 1e-9) return (int)i;
        }
        verts2d.push_back(p);
        return (int)verts2d.size() - 1;
    };
    std::vector<std::array<int, 3>> triIdx;
    for (auto& t : tris2d) triIdx.push_back({findOrAdd(t[0]), findOrAdd(t[1]), findOrAdd(t[2])});

    int nv2d = (int)verts2d.size();
    mesh.nodes.resize(nv2d * (nz + 1));
    for (int k = 0; k <= nz; ++k)
        for (int i = 0; i < nv2d; ++i)
            mesh.nodes[k * nv2d + i] = {verts2d[i].first, verts2d[i].second, k * dz};

    auto nid = [&](int layer, int i2d) { return layer * nv2d + i2d; };

    for (int k = 0; k < nz; ++k) {
        for (auto& t : triIdx) {
            std::array<int, 3> s = t;
            std::sort(s.begin(), s.end()); // canonical order -> consistent face diagonals
            int b0 = nid(k, s[0]), b1 = nid(k, s[1]), b2 = nid(k, s[2]);
            int t0 = nid(k + 1, s[0]), t1 = nid(k + 1, s[1]), t2 = nid(k + 1, s[2]);
            mesh.tets.push_back({b0, b1, b2, t2});
            mesh.tets.push_back({b0, b1, t2, t1});
            mesh.tets.push_back({b0, t1, t2, t0});
        }
    }
    return mesh;
}
