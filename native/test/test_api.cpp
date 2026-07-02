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
    check(r->cellCount > 0, "voxel grid has cells");
    check(r->ci != nullptr && r->cj != nullptr && r->ck != nullptr, "grid index arrays populated");
    check(r->neighbors != nullptr, "neighbour array populated");
    check(r->frequencies != nullptr && r->fields != nullptr, "mode data populated");

    bool ascending = true;
    for (int i = 1; i < r->modeCount; ++i)
        if (r->frequencies[i] < r->frequencies[i - 1]) ascending = false;
    check(ascending, "frequencies are ascending");

    bool allPositive = true;
    for (int i = 0; i < r->modeCount; ++i) if (!(r->frequencies[i] > 0)) allPositive = false;
    check(allPositive, "all frequencies are positive");

    // Every voxel cell's field value across every mode should be finite and
    // within [-1, 1] (the eigenvectors are unit-normalized).
    bool fieldsSane = true;
    for (int m = 0; m < r->modeCount; ++m)
        for (int c = 0; c < r->cellCount; ++c) {
            double v = r->fields[(size_t)m * r->cellCount + c];
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
    // Reference values from a well-resolved solve (resolution 32, 8 modes).
    double reference[3] = {29.03, 40.88, 56.82};

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

    printf("\n%s (%d failure%s)\n", failures == 0 ? "ALL TESTS PASSED" : "TESTS FAILED",
           failures, failures == 1 ? "" : "s");
    return failures == 0 ? 0 : 1;
}
