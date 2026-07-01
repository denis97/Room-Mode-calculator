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
