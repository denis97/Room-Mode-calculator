#pragma once
#include <cstdint>

// C ABI for the native room-mode solver, called from Dart via dart:ffi (see
// lib/core/numeric/native/room_mode_bindings.dart). Solves the room's true
// geometry with FEM (accurate on arbitrary/non-rectilinear floor plans, see
// native/README.md) and returns the field directly on the FEM mesh's own
// boundary surface -- no separate visualization voxel grid, no resampling.
// Field values live at mesh nodes (smooth, shared between adjacent
// triangles); the UI renders them with per-vertex color interpolation.
extern "C" {

// Fields are grouped by size (pointers, then int32s) so the struct has no
// interior padding -- its layout is then unambiguous to mirror exactly in
// Dart's FFI Struct (see lib/core/numeric/native/room_mode_bindings.dart),
// instead of depending on the C compiler's padding rules for a mixed-size
// field order.
struct NativeSolveResult {
    // -- pointers (8-byte aligned) --
    double* nodeX;          // nodeCount: boundary-surface node positions
    double* nodeY;          // nodeCount
    double* nodeZ;          // nodeCount
    int32_t* triangles;     // triCount * 3, indices into the node arrays
    double* frequencies;    // modeCount, ascending
    double* fields;         // modeCount * nodeCount, row-major (mode-major),
                             // the FEM eigenvector's own values at each
                             // boundary node -- no resampling involved
    char* errorMessage;     // null when success != 0

    // -- int32s (4-byte aligned) --
    int32_t nodeCount;
    int32_t triCount;
    int32_t modeCount;
    int32_t success;        // 0 on failure; check errorMessage
};

// [polygonX]/[polygonY]: floor plan vertices (metres), [polygonVertexCount] >= 3.
// [height]: room height (metres). [temperatureC]: air temperature.
// [targetPerAxis]: mesh quality control (higher = finer FEM mesh, more
// accurate but slower). Purely a computation-quality knob now -- it no
// longer has any bearing on visualization detail, since the returned
// surface *is* the solve mesh's own boundary.
// [modeCount]: number of lowest modes to return.
//
// Returns a heap-allocated result; the caller must pass it to
// free_solve_result exactly once when done.
NativeSolveResult* solve_room_modes(
    const double* polygonX, const double* polygonY, int32_t polygonVertexCount,
    double height, double temperatureC, int32_t targetPerAxis, int32_t modeCount);

void free_solve_result(NativeSolveResult* result);

} // extern "C"
