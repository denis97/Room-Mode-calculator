# Native modal solver

A C++ port of the room-mode eigensolver, built for speed (called from Dart via
FFI, see `lib/core/numeric/native/` once wired up) rather than for
readability-first Dart. This directory is validated independently of Flutter:
`cmake && make && ctest` builds and runs `native/test/test_main.cpp` on the
host, no mobile toolchain required.

## Why a native port

Benchmarked against the pure-Dart solver on a 4×3×2 m box: the native version
is **4–13× faster** for the same accuracy (0.2–0.4% vs the analytical modes).
Most of that comes from two things together: native code has no
interpreter/JIT overhead, and the eigensolver here uses a real **Lanczos**
method (a shared Krylov subspace yields several eigenpairs from one process)
instead of the Dart solver's one-mode-at-a-time deflated inverse iteration.

## Two discretizations, one job each

- **FDM** (`laplacian.h`, `polygon_laplacian.h`, `lanczos_eigensolver.h`) — the
  matrix-free finite-volume Neumann Laplacian, same design as
  `lib/core/numeric/`. Kept here as the validation/reference path (it's what
  the Dart solver already does) and because it's the faster method *when
  there's no geometry to get wrong* — i.e. axis-aligned rooms.
- **FEM** (`fem_mesh.h`, `polygon_tet_mesh.h`, `fem_assembly.h`,
  `fem_lanczos.h`) — linear (P1) tetrahedral finite elements, solving the
  generalized eigenproblem `Ku = μMu` via the same Lanczos process (symmetrized
  through the lumped mass matrix). This is the solver that ships for the
  Custom-room tab.

**Why FEM ships for custom rooms:** on a rectangular box, both methods tie —
there's no boundary to approximate, so FDM wins on raw speed (fewer DOFs,
cheaper stencil). On a genuinely non-rectilinear room (tested with a 5-point
star), FEM's body-fitted mesh follows the true boundary exactly at every
resolution, while FDM has to shrink voxels a lot just to trace a pointed
boundary — and even then its error doesn't shrink smoothly (it depends on how
the grid happens to align with the shape). Measured result: FEM at 909 nodes
(23 ms) was **more accurate than FDM at 14,300 cells (456 ms)**. Since the
whole point of the Custom-room tab is non-rectangular geometry, FEM is the
right default there.

## A bug the star case caught

At low resolution, voxelizing a shape with a thin neck (like a star's arms)
can silently **disconnect** the domain into separate pieces. The Neumann
Laplacian has one trivial "constant pressure" null vector *per connected
component* — deflating only a single global mean (what the original Dart
solver does, and what this port initially did too) leaves the extra
components' null vectors undeflated, and they leak through as spurious
near-zero "modes". `null_space.h` fixes this properly: it finds the actual
connected components (union-find over the FDM neighbour graph or the FEM
stiffness matrix's sparsity pattern) and deflates one null vector per
component. `test_main.cpp`'s `testStarFdmNoSpuriousModes` locks in the exact
case that exposed this (a star at resolution 12, which previously returned
`[0.000, 0.000, 45.284]` Hz instead of three real modes).

## The C ABI returns the solve mesh's own boundary, not a voxel grid

`solve_room_modes` (`src/api/room_mode_solver.h`/`.cpp`) used to build a
*second*, independent voxel grid purely for visualization (via
`polygon_laplacian.h`) and resample each mode's FEM field onto it with
nearest-node lookup. That meant "resolution" quietly controlled two
different things at once -- FEM mesh accuracy and voxel visualization
detail -- with no guaranteed relationship between them (a coarse voxel grid
could visibly misrepresent a fine, accurate FEM solve, and vice versa), and
it cost a second meshing pass plus a nearest-neighbour resample on every
solve.

Since a P1 tetrahedral mesh's field is already defined smoothly at its own
nodes, there's no need for any of that: `solve_room_modes` now extracts the
FEM mesh's **boundary surface** directly (the triangular faces belonging to
exactly one tet -- an interior face is shared by two tets and cancels out,
see `extractBoundaryFaces`) and returns those boundary nodes' positions,
the boundary triangle indices, and each mode's field values *at those same
nodes* -- no resampling, no second grid, no separate visualization
resolution. `targetPerAxis` is now purely a computation-quality knob; the 3D
view renders whatever mesh the solver actually used.

The Dart FDM fallback (`lib/core/numeric/modal_analysis.dart`, used when the
native solver is unavailable or rejects a shape) still voxelizes, since FDM
has no other geometry to hand back -- but it converts its voxel grid's
boundary faces into the same `RenderMesh` shape before returning, so the UI
never has to know which solver ran.

## The resolution slider: what it actually buys you, and its real cost

`resolutionToFemParams` (`src/api/room_mode_solver.cpp`) maps the UI's 10-32
resolution slider to an FEM mesh refinement level and extrusion layer count.
Calibrated against a 5×4×3 m box's *analytical* modes (closed-form, so this
is ground truth, not a regression check against a prior solve):

| Level | Box fundamental error | Notes |
|---|---|---|
| 0-2 | 12%-40% | Unusable at any `nz` -- not a "lower quality" option, just wrong. |
| 3 | 0.66-0.69% | Fine on a box, but a concave floor plan (a reflex corner) needs more: the app's default L-room only gets to ~2.4-2.6% here. |
| 4 | ~0.16% | L-room ~0.9-0.95%. The slider's **lowest** setting. |
| 5 | ~0.04% | Comfortably under a 0.1% target. The slider's **highest** setting. |
| 6 | ~0.01% | Measured but not used -- 5-6x the cost of level 5 for an already-tiny improvement. |

Within each level, `nz` (extrusion layers) increases by exactly 1 on every
slider tick, so every position changes the mesh. An earlier version of this
function derived `nz` purely from `level` (`nz = 2*(level+1)`), which meant
whole 6-tick bands of the slider produced an *identical* mesh -- dragging it
did nothing across most of its range. That's fixed now, but it's worth
knowing the failure mode existed, since a resolution-style slider that maps
onto a small number of discrete mesh configurations is an easy trap to fall
back into.

**The real cost of level 5 is not the node count -- it's mesh conditioning
near concave corners.** The app's default L-room at level 4, `nz`=6 needs
1518 unpreconditioned CG iterations per Lanczos step vs. a same-level box's
188 -- an 8x difference the ~2x node-count gap doesn't explain. The cause is
element quality: `earClipTriangulate` + uniform 1-to-4 `subdivide` produces
thinner, more skewed triangles near a reflex (concave) vertex than anywhere
in a convex shape, and those ill-condition the stiffness matrix locally.
`fem_lanczos.h`'s `femCG` now applies a **Jacobi (diagonal) preconditioner**
(`femJacobiPreconditioner`, built once per eigensolve and reused across every
Lanczos-step CG call, since it only depends on the fixed shift) -- that cuts
the L-room's iteration count by roughly 3.5x, and is a straightforward,
unconditional win (same answer, fewer iterations, negligible extra cost).
Eigen's `IncompleteCholesky` was tried too (stronger per-iteration
convergence) but its higher per-iteration cost roughly cancelled the
iteration-count win on this problem, so it wasn't worth the added complexity
and failure modes (a factorization that can fail to produce a valid
preconditioner needs its own fallback path).

Even preconditioned, level 5 on the default L-room takes several seconds
(measured: 5.8-17s across its `nz` range, worse with more requested modes,
on a desktop container -- expect it to be similar or slower on an actual
phone). That's real and not hidden: `custom_room_screen.dart` shows an
inline warning and requires a confirm dialog before running a solve at
resolution ≥ 22 (where the mapping switches to level 5). The `_LabeledSlider`
threshold constant `_slowResolutionThreshold` must stay in sync with this
function's own `step < 12` cutoff.

**Follow-up, not attempted here:** the actual fix for the conditioning
problem is better mesh quality near reflex corners, not a stronger linear
solver. Two directions:
- **Adaptive/quality-bounded refinement** (e.g. Ruppert-style constrained
  Delaunay refinement with a minimum-angle guarantee) instead of uniform
  1-to-4 subdivision -- refines only where it's needed (near the corner) and
  avoids creating slivers in the first place. This directly targets the
  measured root cause and is the more promising direction.
- **P2 (quadratic) tetrahedra** instead of P1 -- higher-order elements need
  fewer DOFs for the same *global* accuracy, but a thin P2 tet is still a
  thin tet: this doesn't address element-quality conditioning near the
  corner specifically, and the assembly/DOF-numbering/boundary-extraction
  changes required are substantially more invasive than switching the
  triangulation strategy. Worth it eventually for the accuracy-per-DOF gain,
  but it's the wrong first lever for *this* problem.

## Mobile wiring

- **Android:** fully wired. `android/app/build.gradle` builds this directory
  via Gradle's `externalNativeBuild { cmake { path "../../native/CMakeLists.txt" } }`,
  producing a `libroom_mode_native.so` per ABI that's bundled into the APK
  automatically. `lib/core/numeric/native/room_mode_bindings.dart` loads it
  with `DynamicLibrary.open('libroom_mode_native.so')`. CI builds and tests
  this on every push (see `.github/workflows/build.yml`).
- **iOS: not wired up yet, and needs a manual Xcode step this repo can't do
  blind.** This environment has no Mac, so an automated edit to
  `ios/Runner.xcodeproj/project.pbxproj` couldn't be verified and risks
  corrupting the Xcode project file. To finish the iOS side on a Mac:
  1. Open `ios/Runner.xcworkspace` in Xcode.
  2. Add `native/src/core` and `native/src/api` to the Runner target's
     "Compile Sources" (drag the folders in, or File → Add Files to "Runner").
  3. Add the fetched Eigen headers to the header search path (either let
     CMake's `FetchContent` populate them via an Xcode "Run Script" build
     phase calling `cmake --build`, or vendor just the `Eigen/` header
     directory under `ios/` and add it to Header Search Paths -- the CMake
     route keeps one source of truth with the Android build).
  4. Ensure C++17 and the same `-O3` optimization are set for those files.
  5. The Dart binding (`RoomModeNativeLibrary._open()`) already expects this:
     since the solver is statically linked into the app binary rather than a
     separate `.dylib`, it uses `DynamicLibrary.process()` (symbol lookup in
     the running process), not `DynamicLibrary.open()`.
  6. Verify with `flutter run` on a real device/simulator, then update this
     note once done.

  Until that's done, the app falls back to the pure-Dart solver on iOS (see
  `lib/state/custom_room_providers.dart`) -- slower, but functionally
  complete, so iOS isn't broken in the meantime.

## Building

```bash
cd native
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release   # fetches Eigen 3.4.0 headers via CMake FetchContent
make -j
ctest --output-on-failure
```

Eigen is fetched at configure time (not vendored) to keep the repository
small — it's a small, well-known, permanently-available dependency, so this
trades a one-time network fetch during the build for not carrying Eigen's
source tree in git history.
