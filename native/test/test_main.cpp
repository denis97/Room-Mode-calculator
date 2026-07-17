// Native solver self-test: runs entirely on the host (no Flutter/mobile
// toolchain needed) so it's cheap to run in CI as a fast correctness gate
// before the mobile build steps.
//
//  1. Box FDM   vs analytical cuboid modes
//  2. Box FEM   vs analytical cuboid modes
//  3. Star FDM  at very low resolution: must NOT produce spurious near-zero
//     "modes" from a voxelization that disconnects the star's thin arms --
//     the bug the connected-components fix in null_space.h addresses.
//  4. Star FEM  sanity: modes strictly positive and ascending.
//
// Exits 0 on success, non-zero (with a message) on any failure.
#include <cstdio>
#include <cmath>
#include <cstdlib>
#include "polygon.h"
#include "polygon_laplacian.h"
#include "polygon_tet_mesh.h"
#include "fem_mesh.h"
#include "fem_assembly.h"
#include "fem_lanczos.h"
#include "lanczos_eigensolver.h"

static int failures = 0;

void check(bool cond, const char* msg) {
    if (!cond) {
        printf("FAIL: %s\n", msg);
        failures++;
    } else {
        printf("PASS: %s\n", msg);
    }
}

double speedOfSound(double tC) { return 331.3 * std::sqrt(1.0 + tC / 273.15); }

void testBoxFdm() {
    printf("\n-- Box FDM vs analytical --\n");
    Polygon rect;
    rect.verts = {{0, 0}, {4, 0}, {4, 3}, {0, 3}};
    PolygonGridInfo info;
    auto op = buildPolygonLaplacian(rect, 2.0, 12, info);
    double c = speedOfSound(20.0703);
    auto pairs = lanczosSmallestEigenpairs(op, 3, 20);
    double expected[3] = {42.875, 57.167, 71.458};
    for (int i = 0; i < 3; ++i) {
        double f = c * std::sqrt(std::max(pairs[i].eigenvalue, 0.0)) / (2 * M_PI);
        double err = 100.0 * std::fabs(f - expected[i]) / expected[i];
        char msg[128];
        snprintf(msg, sizeof(msg), "mode %d = %.3f Hz (expected %.3f, err %.2f%%)", i, f, expected[i], err);
        check(err < 3.0, msg);
    }
}

void testBoxFem() {
    printf("\n-- Box FEM vs analytical --\n");
    auto mesh = buildBoxTetMesh(4, 3, 2, 12);
    auto sys = assembleFem(boxMeshNodes(mesh), mesh.tets);
    std::vector<double> minvSqrt(sys.numNodes);
    for (int i = 0; i < sys.numNodes; ++i) minvSqrt[i] = 1.0 / std::sqrt(sys.lumpedM[i]);
    FemOperator op{sys.K, minvSqrt};
    auto pairs = femLanczosSmallestEigenpairs(op, sys.numNodes, 3, 20);
    double c = speedOfSound(20.0703);
    double expected[3] = {42.875, 57.167, 71.458};
    for (int i = 0; i < 3; ++i) {
        double f = c * std::sqrt(std::max(pairs[i].eigenvalue, 0.0)) / (2 * M_PI);
        double err = 100.0 * std::fabs(f - expected[i]) / expected[i];
        char msg[128];
        snprintf(msg, sizeof(msg), "mode %d = %.3f Hz (expected %.3f, err %.2f%%)", i, f, expected[i], err);
        check(err < 3.0, msg);
    }
}

void testStarFdmNoSpuriousModes() {
    printf("\n-- Star FDM at low resolution: no spurious zero modes --\n");
    Polygon star = makeStarPolygon5();
    PolygonGridInfo info;
    // res=12 was the exact case that produced two spurious 0.000 Hz "modes"
    // before the connected-components fix (thin arms disconnected).
    auto op = buildPolygonLaplacian(star, 3.0, 12, info);
    auto pairs = lanczosSmallestEigenpairs(op, 3, 20);
    for (int i = 0; i < (int)pairs.size(); ++i) {
        double c = speedOfSound(20.0);
        double f = c * std::sqrt(std::max(pairs[i].eigenvalue, 0.0)) / (2 * M_PI);
        char msg[128];
        snprintf(msg, sizeof(msg), "mode %d = %.3f Hz is a real (non-spurious) mode", i, f);
        check(f > 1.0, msg); // a genuine room mode is never a fraction of a Hz
    }
}

void testStarFemSanity() {
    printf("\n-- Star FEM sanity --\n");
    Polygon star = makeStarPolygon5();
    auto tris = earClipTriangulate(star);
    tris = subdivide(subdivide(tris));
    auto mesh = extrudeToTets(tris, 3.0, 8);
    auto sys = assembleFem(mesh.nodes, mesh.tets);
    std::vector<double> minvSqrt(sys.numNodes);
    for (int i = 0; i < sys.numNodes; ++i) minvSqrt[i] = 1.0 / std::sqrt(sys.lumpedM[i]);
    FemOperator op{sys.K, minvSqrt};
    auto pairs = femLanczosSmallestEigenpairs(op, sys.numNodes, 3, 20);
    check(pairs.size() == 3, "returns the requested number of modes");
    for (int i = 0; i < (int)pairs.size(); ++i) {
        char msg[128];
        snprintf(msg, sizeof(msg), "mode %d eigenvalue %.4f is positive", i, pairs[i].eigenvalue);
        check(pairs[i].eigenvalue > 0, msg);
        if (i > 0) {
            snprintf(msg, sizeof(msg), "mode %d >= mode %d (ascending)", i, i - 1);
            check(pairs[i].eigenvalue >= pairs[i - 1].eigenvalue, msg);
        }
    }
}

void testEarClipOnConcavePolygon() {
    printf("\n-- Ear-clipping on a concave (non-star-shaped-from-centroid) L-room --\n");
    // A deep, narrow L: the centroid sits outside the polygon entirely, so
    // fan-triangulation-from-centroid would silently produce a broken mesh
    // here -- exactly the case ear-clipping needs to get right.
    Polygon lShape;
    lShape.verts = {{0, 0}, {6, 0}, {6, 1}, {1, 1}, {1, 6}, {0, 6}};
    double trueArea = lShape.area();

    auto tris = earClipTriangulate(lShape);
    double triArea = 0;
    for (auto& t : tris) {
        double x1 = t[0].first, y1 = t[0].second;
        double x2 = t[1].first, y2 = t[1].second;
        double x3 = t[2].first, y3 = t[2].second;
        triArea += std::fabs((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)) / 2.0;
    }
    char msg[160];
    snprintf(msg, sizeof(msg), "triangulated area %.4f matches true polygon area %.4f",
             triArea, trueArea);
    check(std::fabs(triArea - trueArea) < 1e-6, msg);

    auto mesh = extrudeToTets(subdivide(tris), 2.5, 4);
    auto sys = assembleFem(mesh.nodes, mesh.tets);
    std::vector<double> minvSqrt(sys.numNodes);
    for (int i = 0; i < sys.numNodes; ++i) minvSqrt[i] = 1.0 / std::sqrt(sys.lumpedM[i]);
    FemOperator op{sys.K, minvSqrt};
    auto pairs = femLanczosSmallestEigenpairs(op, sys.numNodes, 3, 20);
    check(pairs.size() == 3, "L-room FEM returns the requested number of modes");
    for (auto& p : pairs) check(p.eigenvalue > 0, "L-room mode eigenvalue is positive");
}

double triangleMinAngleDeg(const Tri2D& t) {
    auto angle = [](Pt2 a, Pt2 b, Pt2 c) { // angle at b
        double ux = a.first - b.first, uy = a.second - b.second;
        double vx = c.first - b.first, vy = c.second - b.second;
        double cosv = (ux * vx + uy * vy) /
                      (std::sqrt(ux * ux + uy * uy) * std::sqrt(vx * vx + vy * vy));
        return std::acos(std::max(-1.0, std::min(1.0, cosv))) * 180.0 / M_PI;
    };
    return std::min({angle(t[2], t[0], t[1]), angle(t[0], t[1], t[2]), angle(t[1], t[2], t[0])});
}

void testDelaunayRefinementFixesSlivers() {
    printf("\n-- Delaunay refinement fixes ear-clipping's slivers --\n");
    // Regression: earClipTriangulate has no quality objective of its own --
    // it greedily takes the first valid ear -- and on the app's default
    // L-room that used to leave a 5.19 degree sliver in the *base*
    // triangulation. Since uniform 1-to-4 subdivision splits every triangle
    // into 4 similar copies (same angles, smaller size), that sliver used to
    // persist unchanged at every mesh resolution and was the real cause of
    // the linear solver needing ~8x more CG iterations on this shape than a
    // same-size box (see native/README.md). earClipTriangulate now applies
    // a Delaunay edge-flip pass (delaunayRefine) to its own output, which
    // measured at bringing this specific case up to 38.66 degrees -- matches
    // a plain box's own triangulation quality, since the defect was a bad
    // diagonal choice, not anything inherent to the L-room's geometry.
    Polygon lRoom;
    lRoom.verts = {{0, 0}, {5, 0}, {5, 3}, {2.5, 3}, {2.5, 5}, {0, 5}};
    auto tris = earClipTriangulate(lRoom);

    double minAngle = 180.0;
    for (auto& t : tris) minAngle = std::min(minAngle, triangleMinAngleDeg(t));
    char msg[128];
    snprintf(msg, sizeof(msg), "default L-room's base triangulation has no sliver (min angle %.2f degrees)",
             minAngle);
    check(minAngle > 20.0, msg);

    // Delaunay flips only reorder existing diagonals -- they must never
    // change the polygon's actual area.
    double trueArea = lRoom.area();
    double triArea = 0;
    for (auto& t : tris) {
        double x1 = t[0].first, y1 = t[0].second;
        double x2 = t[1].first, y2 = t[1].second;
        double x3 = t[2].first, y3 = t[2].second;
        triArea += std::fabs((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)) / 2.0;
    }
    snprintf(msg, sizeof(msg), "refined triangulation area %.4f still matches true polygon area %.4f",
             triArea, trueArea);
    check(std::fabs(triArea - trueArea) < 1e-6, msg);
}

void testDelaunayRefineHandlesManyPointsWithoutOverlap() {
    printf("\n-- Delaunay refinement on a many-point floor plan: no overlapping triangles --\n");
    // Regression: delaunayRefine used to apply every flip a single pass found
    // from one stale snapshot of the mesh. Once a floor plan has enough
    // points to put several near-cocircular quads up for a flip at once
    // (easy to hit with a many-vertex custom shape, e.g. a smoothly curved
    // or densely-edited outline), the same triangle could be a candidate for
    // two different flips in that one pass. The second flip then read that
    // triangle's already-mutated (by the first flip) vertices as if they
    // were still original, producing a geometrically invalid triangle that
    // overlaps its neighbours -- with no error raised, silently poisoning
    // the extruded FEM mesh and everything downstream (wrong or unstable
    // mode frequencies, a visibly tangled 3D mesh). Triangulated area
    // exceeding the true polygon area is the tell: it can only happen if
    // triangles overlap, since a valid triangulation partitions the polygon
    // exactly.
    unsigned seed = 12345;
    auto rnd = [&]() { seed = seed * 1103515245u + 12345u; return ((seed >> 16) & 0x7fff) / 32768.0; };
    Polygon manyPt;
    const int n = 60;
    for (int i = 0; i < n; ++i) {
        double angle = 2 * M_PI * i / n;
        double jitter = (rnd() - 0.5) * 0.001; // tiny, as real edits produce
        double r = 3.0 + jitter;
        manyPt.verts.push_back({5.0 + r * std::cos(angle), 5.0 + r * std::sin(angle)});
    }
    double trueArea = manyPt.area();
    auto tris = earClipTriangulate(manyPt);
    double sumArea = 0;
    for (auto& t : tris) {
        double x1 = t[0].first, y1 = t[0].second;
        double x2 = t[1].first, y2 = t[1].second;
        double x3 = t[2].first, y3 = t[2].second;
        sumArea += std::fabs((x2 - x1) * (y3 - y1) - (x3 - x1) * (y2 - y1)) / 2.0;
    }
    char msg[160];
    snprintf(msg, sizeof(msg), "%d-vertex triangulation area %.4f matches true polygon area %.4f (no overlap)",
             n, sumArea, trueArea);
    check(std::fabs(sumArea - trueArea) < 1e-6, msg);
}

int main() {
    testBoxFdm();
    testBoxFem();
    testStarFdmNoSpuriousModes();
    testStarFemSanity();
    testEarClipOnConcavePolygon();
    testDelaunayRefinementFixesSlivers();
    testDelaunayRefineHandlesManyPointsWithoutOverlap();
    printf("\n%s (%d failure%s)\n", failures == 0 ? "ALL TESTS PASSED" : "TESTS FAILED",
           failures, failures == 1 ? "" : "s");
    return failures == 0 ? 0 : 1;
}
