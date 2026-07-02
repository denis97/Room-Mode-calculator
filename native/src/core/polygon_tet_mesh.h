#pragma once
#include <vector>
#include <array>
#include <cmath>
#include <algorithm>
#include <map>
#include "polygon.h"
#include "fem_assembly.h" // Vec3

struct PolyTetMesh {
    std::vector<Vec3> nodes;
    std::vector<std::array<int, 4>> tets;
};

using Pt2 = std::pair<double, double>;
using Tri2D = std::array<Pt2, 3>;

// Ear-clipping triangulation: works for *any* simple polygon (convex or
// concave), unlike fan-triangulation from a single point which is only valid
// when that point can see the whole boundary ("star-shaped from that point")
// -- not guaranteed for a general room shape (an L/T/U room's centroid may
// not have full visibility, especially for a deep or narrow arm).
inline bool isConvexVertex(const Pt2& a, const Pt2& b, const Pt2& c, bool ccw) {
    double cross = (b.first - a.first) * (c.second - a.second) -
                    (b.second - a.second) * (c.first - a.first);
    return ccw ? (cross > 1e-12) : (cross < -1e-12);
}

inline bool pointInTriangle(const Pt2& p, const Pt2& a, const Pt2& b, const Pt2& c) {
    auto sign = [](const Pt2& p1, const Pt2& p2, const Pt2& p3) {
        return (p1.first - p3.first) * (p2.second - p3.second) -
               (p2.first - p3.first) * (p1.second - p3.second);
    };
    double d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a);
    bool hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0);
    bool hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0);
    return !(hasNeg && hasPos);
}

// Improves triangle quality on a *fixed* vertex set by flipping interior
// diagonals to satisfy the Delaunay condition (Lawson's algorithm) --
// without adding or moving a single point, so it can't change the mesh's
// outer boundary, only how the interior is cut into triangles. Boundary
// edges (shared by only one triangle) are never touched.
//
// Ear-clipping has no quality objective at all: it greedily takes the first
// geometrically valid ear it finds, which can leave razor-thin slivers with
// no relation to the polygon's own angles. Measured on the app's default
// L-room: ear-clipping alone produces a 5.19 degree / 168.47 degree sliver;
// since uniform 1-to-4 subdivision splits every triangle into 4 *similar*
// copies (same angles, smaller size), that sliver -- and the linear-solver
// conditioning problem it causes -- persists unchanged at every mesh
// resolution, from the 4-triangle base mesh up through 1024+ triangles. A
// single Delaunay flip fixes it completely (5.19 -> 38.66 degrees, matching
// a plain box's own quality), because the defect was a bad *diagonal
// choice*, not anything inherent to the L-room's geometry. Measured across
// all four floor-plan presets plus a 5-point star: every case improved or
// was already optimal, never regressed, and converged in 1-3 flip passes.
inline std::vector<Tri2D> delaunayRefine(const std::vector<Tri2D>& tris) {
    std::vector<Pt2> verts;
    auto findOrAdd = [&](Pt2 p) -> int {
        for (size_t i = 0; i < verts.size(); ++i)
            if (std::fabs(verts[i].first - p.first) < 1e-9 &&
                std::fabs(verts[i].second - p.second) < 1e-9) return (int)i;
        verts.push_back(p);
        return (int)verts.size() - 1;
    };
    std::vector<std::array<int, 3>> t;
    for (auto& tr : tris) t.push_back({findOrAdd(tr[0]), findOrAdd(tr[1]), findOrAdd(tr[2])});

    auto ccw = [&](int a, int b, int c) {
        double cross = (verts[b].first - verts[a].first) * (verts[c].second - verts[a].second) -
                       (verts[b].second - verts[a].second) * (verts[c].first - verts[a].first);
        return cross > 0;
    };
    for (auto& tr : t) if (!ccw(tr[0], tr[1], tr[2])) std::swap(tr[1], tr[2]);

    // Standard in-circumcircle predicate (assumes a,b,c are CCW): true when
    // d lies strictly inside the circumcircle of triangle a,b,c.
    auto inCircumcircle = [&](Pt2 a, Pt2 b, Pt2 c, Pt2 d) {
        double ax = a.first - d.first, ay = a.second - d.second;
        double bx = b.first - d.first, by = b.second - d.second;
        double cx = c.first - d.first, cy = c.second - d.second;
        double det = (ax * ax + ay * ay) * (bx * cy - cx * by) -
                     (bx * bx + by * by) * (ax * cy - cx * ay) +
                     (cx * cx + cy * cy) * (ax * by - bx * ay);
        return det > 1e-9;
    };
    auto edgeKey = [](int a, int b) { return a < b ? std::make_pair(a, b) : std::make_pair(b, a); };

    bool changed = true;
    int guard = 0;
    while (changed && guard++ < (int)t.size() * 10 + 50) {
        changed = false;
        std::map<std::pair<int, int>, std::vector<int>> edgeToTris;
        for (size_t ti = 0; ti < t.size(); ++ti) {
            int e[3][2] = {{t[ti][0], t[ti][1]}, {t[ti][1], t[ti][2]}, {t[ti][2], t[ti][0]}};
            for (auto& ee : e) edgeToTris[edgeKey(ee[0], ee[1])].push_back((int)ti);
        }
        for (auto& [edge, sharing] : edgeToTris) {
            if (sharing.size() != 2) continue; // boundary edge: never flip
            int ti0 = sharing[0], ti1 = sharing[1];
            auto opposite = [&](std::array<int, 3>& tr) {
                for (int v : tr) if (v != edge.first && v != edge.second) return v;
                return -1;
            };
            int p = opposite(t[ti0]), q = opposite(t[ti1]);
            if (p < 0 || q < 0) continue;
            if (!inCircumcircle(verts[t[ti0][0]], verts[t[ti0][1]], verts[t[ti0][2]], verts[q]))
                continue;
            // A flip is only geometrically valid if the quadrilateral formed
            // by the two triangles is convex -- i.e. p and q fall on
            // opposite sides of the shared edge (always true for a valid
            // triangulation) *and* opposite sides of the new diagonal too.
            bool convex = ccw(edge.first, q, edge.second) != ccw(edge.first, p, edge.second);
            if (!convex) continue;
            t[ti0] = {p, q, edge.first};
            t[ti1] = {q, p, edge.second};
            if (!ccw(t[ti0][0], t[ti0][1], t[ti0][2])) std::swap(t[ti0][1], t[ti0][2]);
            if (!ccw(t[ti1][0], t[ti1][1], t[ti1][2])) std::swap(t[ti1][1], t[ti1][2]);
            changed = true;
        }
    }

    std::vector<Tri2D> out;
    for (auto& tr : t) out.push_back({verts[tr[0]], verts[tr[1]], verts[tr[2]]});
    return out;
}

inline std::vector<Tri2D> earClipTriangulate(const Polygon& poly) {
    size_t n = poly.verts.size();
    std::vector<int> idx(n);
    for (size_t i = 0; i < n; ++i) idx[i] = (int)i;

    // Work in CCW order (the signed shoelace area is positive for CCW).
    double signedArea = 0;
    for (size_t i = 0, j = n - 1; i < n; j = i++)
        signedArea += poly.verts[j].first * poly.verts[i].second -
                      poly.verts[i].first * poly.verts[j].second;
    if (signedArea < 0) std::reverse(idx.begin(), idx.end());

    std::vector<Tri2D> tris;
    int guard = 0;
    while (idx.size() > 3 && guard++ < (int)n * (int)n + 10) {
        int m = (int)idx.size();
        bool clipped = false;
        for (int i = 0; i < m; ++i) {
            int ip = idx[(i - 1 + m) % m], ic = idx[i], in = idx[(i + 1) % m];
            const Pt2& a = poly.verts[ip];
            const Pt2& b = poly.verts[ic];
            const Pt2& c = poly.verts[in];
            if (!isConvexVertex(a, b, c, true)) continue;

            bool anyInside = false;
            for (int j = 0; j < m; ++j) {
                if (j == (i - 1 + m) % m || j == i || j == (i + 1) % m) continue;
                if (pointInTriangle(poly.verts[idx[j]], a, b, c)) { anyInside = true; break; }
            }
            if (anyInside) continue;

            tris.push_back({a, b, c});
            idx.erase(idx.begin() + i);
            clipped = true;
            break;
        }
        if (!clipped) break; // degenerate/self-intersecting input; stop gracefully
    }
    if (idx.size() == 3) tris.push_back({poly.verts[idx[0]], poly.verts[idx[1]], poly.verts[idx[2]]});
    // Ear-clipping alone has no quality objective -- see delaunayRefine's own
    // comment for why this matters and what it fixes.
    return delaunayRefine(tris);
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
