#pragma once
#include <cstdint>

// C ABI for the native room-mode solver, called from Dart via dart:ffi (see
// lib/core/numeric/native/room_mode_bindings.dart). Solves the room's true
// geometry with FEM (accurate on arbitrary/non-rectilinear floor plans, see
// native/README.md), then resamples each mode's field onto a voxel grid so
// the result matches the shape the existing Dart VoxelGrid/ComputedMode/
// ModalAnalysisResult classes -- and the UI widgets built around them --
// already expect. No UI code needs to change to consume this.
extern "C" {

struct NativeSolveResult {
    // Voxel grid geometry (visualization only -- the eigenvalues/frequencies
    // come from the true FEM mesh, not this grid).
    int32_t nx, ny, nz;
    double h, originX, originY, originZ;
    int32_t cellCount;
    int32_t* ci;         // cellCount
    int32_t* cj;         // cellCount
    int32_t* ck;         // cellCount
    int32_t* neighbors;  // cellCount * 6

    // Modes, ascending by frequency.
    int32_t modeCount;
    double* frequencies;  // modeCount
    double* fields;       // modeCount * cellCount, row-major (mode-major),
                           // resampled from the FEM solution onto the voxel grid

    int32_t success;      // 0 on failure; check errorMessage
    char* errorMessage;   // null when success != 0
};

// [polygonX]/[polygonY]: floor plan vertices (metres), [polygonVertexCount] >= 3.
// [height]: room height (metres). [temperatureC]: air temperature.
// [targetPerAxis]: resolution control (same meaning/range as the Dart
// FloorPlan.resolution slider, 10-32) -- drives both the FEM mesh refinement
// and the visualization voxel grid's cell size.
// [modeCount]: number of lowest modes to return.
//
// Returns a heap-allocated result; the caller must pass it to
// free_solve_result exactly once when done.
NativeSolveResult* solve_room_modes(
    const double* polygonX, const double* polygonY, int32_t polygonVertexCount,
    double height, double temperatureC, int32_t targetPerAxis, int32_t modeCount);

void free_solve_result(NativeSolveResult* result);

} // extern "C"
