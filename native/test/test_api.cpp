// Exercises the actual C ABI (room_mode_solver.h) end-to-end, the same
// surface Dart calls via FFI -- catches marshaling bugs that calling the C++
// internals directly (test_main.cpp) wouldn't.
#include <cstdio>
#include <cmath>
#include <vector>
#include "../src/api/room_mode_solver.h"

static int failures = 0;

void check(bool cond, const char* msg) {
    printf("%s: %s\n", cond ? "PASS" : "FAIL", msg);
    if (!cond) failures++;
}

int main() {
    // Deep L-room: the same shape that requires ear-clipping (not fan
    // triangulation) to mesh correctly.
    std::vector<double> px = {0, 6, 6, 1, 1, 0};
    std::vector<double> py = {0, 0, 1, 1, 6, 6};

    auto* r = solve_room_modes(px.data(), py.data(), (int32_t)px.size(),
                                /*height=*/2.5, /*temperatureC=*/20.0,
                                /*targetPerAxis=*/16, /*modeCount=*/5);

    check(r != nullptr, "returns a non-null result");
    check(r->success != 0, "reports success");
    check(r->modeCount == 5, "returns the requested mode count");
    check(r->nodeCount > 0, "boundary surface has nodes");
    check(r->triCount > 0, "boundary surface has triangles");
    check(r->nodeX != nullptr && r->nodeY != nullptr && r->nodeZ != nullptr,
          "node position arrays populated");
    check(r->triangles != nullptr, "triangle index array populated");
    check(r->frequencies != nullptr && r->fields != nullptr, "mode data populated");

    bool ascending = true;
    for (int i = 1; i < r->modeCount; ++i)
        if (r->frequencies[i] < r->frequencies[i - 1]) ascending = false;
    check(ascending, "frequencies are ascending");

    bool allPositive = true;
    for (int i = 0; i < r->modeCount; ++i) if (!(r->frequencies[i] > 0)) allPositive = false;
    check(allPositive, "all frequencies are positive");

    // Every triangle index should reference a valid node.
    bool indicesInRange = true;
    for (int i = 0; i < r->triCount * 3; ++i)
        if (r->triangles[i] < 0 || r->triangles[i] >= r->nodeCount) indicesInRange = false;
    check(indicesInRange, "triangle indices are within node range");

    // Every node's field value across every mode should be finite and
    // within [-1, 1] (the eigenvectors are unit-normalized).
    bool fieldsSane = true;
    for (int m = 0; m < r->modeCount; ++m)
        for (int i = 0; i < r->nodeCount; ++i) {
            double v = r->fields[(size_t)m * r->nodeCount + i];
            if (!std::isfinite(v) || v < -1.0001 || v > 1.0001) fieldsSane = false;
        }
    check(fieldsSane, "field values are finite and in [-1, 1]");

    free_solve_result(r);

    // Error path: degenerate input should report failure, not crash.
    std::vector<double> tooFew = {0, 1};
    auto* bad = solve_room_modes(tooFew.data(), tooFew.data(), 2, 2.5, 20.0, 16, 5);
    check(bad != nullptr && bad->success == 0, "degenerate polygon reports failure, not a crash");
    check(bad->errorMessage != nullptr, "failure includes an error message");
    free_solve_result(bad);

    // Regression: a low resolution slider value used to under-mesh the FEM
    // solve when the requested mode count was large relative to the mesh's
    // node count (a mesh with too few nodes to support the mode count gives
    // severely wrong low-order frequencies, not just "less precise" ones --
    // e.g. the app's default L-room at resolution 12 with 8 modes gave 31%
    // error on the fundamental before this fix). resolutionToFemParams now
    // bumps the mesh level up (independent of the raw resolution value) until
    // the node count is safely above the requested mode count.
    std::vector<double> lx = {0, 5, 5, 2.5, 2.5, 0};
    std::vector<double> ly = {0, 0, 3, 3, 5, 5};
    // Reference values from the current mapping's own best (resolution 32,
    // 8 modes, level 5).
    double reference[3] = {28.310, 40.693, 57.110};

    auto* low = solve_room_modes(lx.data(), ly.data(), (int32_t)lx.size(),
                                  /*height=*/3.0, /*temperatureC=*/20.0,
                                  /*targetPerAxis=*/12, /*modeCount=*/8);
    check(low != nullptr && low->success != 0, "default room at resolution 12 solves successfully");
    if (low != nullptr && low->success != 0) {
        for (int i = 0; i < 3; ++i) {
            double err = 100.0 * std::fabs(low->frequencies[i] - reference[i]) / reference[i];
            char msg[128];
            snprintf(msg, sizeof(msg), "mode %d at resolution 12 is within 15%% of the reference (got %.2f%%)",
                      i, err);
            check(err < 15.0, msg);
        }
    }
    if (low != nullptr) free_solve_result(low);

    // The resolution slider must give a genuinely different mesh at every
    // tick, not just every 6th one (the original dead-zone bug: nz used to
    // be a pure function of level, so level 0-2 wasted most of the slider's
    // range). Two positions that used to fall in the same dead zone must
    // now produce measurably different results.
    auto* atTen = solve_room_modes(lx.data(), ly.data(), (int32_t)lx.size(),
                                    3.0, 20.0, /*targetPerAxis=*/10, 8);
    auto* atFifteen = solve_room_modes(lx.data(), ly.data(), (int32_t)lx.size(),
                                        3.0, 20.0, /*targetPerAxis=*/15, 8);
    check(atTen != nullptr && atTen->success != 0 && atFifteen != nullptr && atFifteen->success != 0,
          "both dead-zone-probe resolutions solve successfully");
    if (atTen && atTen->success && atFifteen && atFifteen->success) {
        check(std::fabs(atTen->frequencies[0] - atFifteen->frequencies[0]) > 1e-6,
              "resolution 10 and 15 (previously in the same dead zone) give different results");
    }
    if (atTen) free_solve_result(atTen);
    if (atFifteen) free_solve_result(atFifteen);

    // Definitive accuracy check against the analytical model: a rectangular
    // room has an exact closed-form solution
    // (f(p,q,r) = c/2 * sqrt((p/L)^2+(q/W)^2+(r/H)^2)), so unlike the L-room
    // above this isn't just a regression check against a prior solve, it's
    // ground truth. At the slider's lowest setting the fundamental must be
    // within 2%; the box is the easy case (no boundary to approximate), so
    // this has generous headroom over what a real (concave) room gets.
    {
        double L = 5, W = 4, H = 3;
        std::vector<double> bx = {0, L, L, 0}, by = {0, 0, W, W};
        double c = 331.3 * std::sqrt(1.0 + 20.0703 / 273.15);
        double f0Analytical = c / 2.0 * std::sqrt(1.0 / (L * L)); // f(1,0,0)

        auto* box = solve_room_modes(bx.data(), by.data(), (int32_t)bx.size(),
                                      H, 20.0703, /*targetPerAxis=*/10, /*modeCount=*/8);
        check(box != nullptr && box->success != 0, "box at the lowest resolution solves successfully");
        if (box != nullptr && box->success != 0) {
            double err = 100.0 * std::fabs(box->frequencies[0] - f0Analytical) / f0Analytical;
            char msg[128];
            snprintf(msg, sizeof(msg),
                     "box fundamental at the lowest resolution is within 2%% of the analytical value (got %.3f%%)",
                     err);
            check(err < 2.0, msg);
        }
        if (box != nullptr) free_solve_result(box);
    }

    printf("\n%s (%d failure%s)\n", failures == 0 ? "ALL TESTS PASSED" : "TESTS FAILED",
           failures, failures == 1 ? "" : "s");
    return failures == 0 ? 0 : 1;
}
