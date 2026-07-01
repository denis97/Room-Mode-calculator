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
    auto tris = fanTriangulate(star);
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

int main() {
    testBoxFdm();
    testBoxFem();
    testStarFdmNoSpuriousModes();
    testStarFemSanity();
    printf("\n%s (%d failure%s)\n", failures == 0 ? "ALL TESTS PASSED" : "TESTS FAILED",
           failures, failures == 1 ? "" : "s");
    return failures == 0 ? 0 : 1;
}
