# Room Mode Calculator

A Flutter app (Android first, iOS later) that calculates the **acoustic room
modes** of a room — the standing-wave resonances that colour the low-frequency
sound of any space. It covers both the easy case and the hard one:

- **Cuboid** rooms via the exact analytical formula (like
  [amroc](https://amcoustics.com/tools/amroc/)), and
- **Arbitrary (non-rectangular)** rooms via an on-device numerical eigensolver
  (the same idea as [amroc pro](https://amcoustics.com/tools/amroc-pro/), which
  uses the Finite Element Method).

Everything runs **fully offline** on the device.

---

## Table of contents

- [Features](#features)
- [The physics & math](#the-physics--math)
  - [What a room mode is](#what-a-room-mode-is)
  - [Analytical cuboid modes](#analytical-cuboid-modes)
  - [Speed of sound](#speed-of-sound)
  - [Mode types & strength](#mode-types--strength)
  - [Pressure field](#pressure-field)
  - [Note mapping](#note-mapping)
  - [Room-quality metrics](#room-quality-metrics)
- [Speaker & listener placement](#speaker--listener-placement)
  - [Mode excitation & audibility](#mode-excitation--audibility)
  - [Stereo pairs & coherent summation](#stereo-pairs--coherent-summation)
  - [Predicted frequency response](#predicted-frequency-response)
  - [The placement advisor](#the-placement-advisor)
- [Numerical solver for arbitrary rooms](#numerical-solver-for-arbitrary-rooms)
  - [The governing equation (both paths)](#1-the-governing-equation-both-paths)
  - [Native FEM path (what ships on Android)](#2-native-fem-path-what-ships-on-android)
  - [Dart FVM/FDM path (fallback + reference oracle)](#3-dart-fvmfdm-path-fallback--reference-oracle)
  - [Running off the UI thread (both paths)](#4-running-off-the-ui-thread-both-paths)
  - [Visualization](#5-visualization)
- [Project layout](#project-layout)
- [Developing](#developing)
- [Testing](#testing)
- [CI & release artifacts](#ci--release-artifacts)
- [Roadmap](#roadmap)

---

## Features

The app is a two-screen **Setup → Viewer** flow, with a segmented toggle at the
top of Setup choosing between a **Cuboid** room and a **Custom shape**.

### Setup

- **Cuboid** — steppers for length, width, height and air temperature, with a
  live isometric preview and a running mode count. "Calculate modes" opens the
  Viewer.
- **Custom shape** — a full **floor-plan editor**: draw the room's floor
  polygon on a metre grid (drag vertices, tap an edge to insert one, long-press
  to remove; tap to expand to a full-screen canvas with two-finger pan/zoom and
  zoom-adaptive magnetic snapping). Presets for Rectangle / L / T / U shapes,
  plus solver resolution and mode-count sliders. Edge lengths and an
  area/volume readout show the real size. "Compute modes" runs the solver.

### Viewer

Both room kinds share the same viewer chrome:

- **Resonances axis** — every mode on a frequency line. For the cuboid it is
  coloured by type and sized by strength, with the Schroeder frequency marked;
  for custom rooms each solved mode is a tappable peak. Tap to select.
- **Rotatable 3D pressure field** — the room's boundary coloured by the selected
  mode's pressure (cyan → dark → pink diverging gradient); drag to orbit.
- **Mode navigator** — step or scrub through modes; a bottom sheet lists them
  all (frequency, indices `(p,q,r)`, type, nearest note).
- **Expandable tool sections** (cuboid): **Speaker placement** (see below),
  **piano keyboard** (tap a key to *hear* the pitch — a sine tone synthesised on
  the fly), **pressure slice** at an adjustable ear height, and **room quality**
  (Schroeder frequency, room ratio vs recommended ratios, and the Bonello
  criterion with a ⅓-octave modal-density bar chart).

Everything is live and offline; editing the room re-derives the whole viewer.

---

## The physics & math

### What a room mode is

Sound reflects off a room's boundaries. At certain frequencies the reflections
reinforce into a **standing wave** — a fixed spatial pattern of pressure
maxima (**antinodes**) and minima (**nodes**) that rings at a specific
frequency. These are the room's *modes*. In the low-frequency range they are
sparse and audible as booms and nulls; that is what this app maps out.

### Analytical cuboid modes

For a rigid-wall rectangular room $L \times W \times H$ (metres) the modal
frequencies have a closed form:

$$f_{p,q,r} = \frac{c}{2}\sqrt{\left(\frac{p}{L}\right)^2 + \left(\frac{q}{W}\right)^2 + \left(\frac{r}{H}\right)^2}$$

with integer indices $p, q, r \in \{0, 1, 2, \dots\}$ (not all zero) and $c$ the
speed of sound. The solver enumerates every $(p, q, r)$ up to the chosen cutoff.
Since the smallest-frequency mode for a given index is axial,
$f_{n,0,0} = \tfrac{cn}{2L}$, the per-axis index bound is
$n \le \tfrac{2 f_\text{max} L}{c}$; the solver iterates to that bound and keeps
modes with $f \le f_\text{max}$, sorted by frequency. Implemented in
`lib/core/acoustics/mode_calculator.dart`.

### Speed of sound

Temperature-dependent, in dry air:

$$c = 331.3\,\sqrt{1 + \frac{T}{273.15}}\ \text{m/s} \qquad (\approx 343\ \text{m/s at } 20\,^\circ\text{C})$$

`lib/core/acoustics/speed_of_sound.dart`.

### Mode types & strength

A mode is classified by how many indices are non-zero:

| non-zero indices | type       | relative strength |
|------------------|------------|-------------------|
| 1                | axial      | 4                 |
| 2                | tangential | 2                 |
| 3                | oblique    | 1                 |

Axial modes bounce between one pair of parallel walls and are the strongest;
oblique modes involve all six walls and are weakest. `lib/core/acoustics/mode.dart`.

### Pressure field

The normalized standing-pressure field of mode $(p, q, r)$ is a product of
cosines:

$$P(x, y, z) = \cos\frac{p\pi x}{L}\,\cos\frac{q\pi y}{W}\,\cos\frac{r\pi z}{H} \in [-1, 1]$$

Antinodes ($|P| = 1$) sit at the walls; nodal planes ($P = 0$) are where any
cosine crosses zero. `lib/core/acoustics/pressure_field.dart` samples this onto
a grid for the heatmaps and the 3D view. This same $P$ is the mode shape
$\psi_n$ used by the placement math below.

### Note mapping

To place modes on a keyboard and let you hear them, frequencies map to MIDI /
musical pitch:

$$\text{midi} = 69 + 12\log_2\frac{f}{440} \qquad (\text{A4} = 440\ \text{Hz} = \text{MIDI } 69)$$

`lib/core/acoustics/note_mapping.dart`.

### Room-quality metrics

`lib/core/acoustics/schroeder.dart` and `room_ratios.dart`:

- **Schroeder frequency** — boundary between the modal region (discrete modes)
  and the diffuse region (dense overlap): $f_s = 2000\,\sqrt{\text{RT60} / V}$,
  with $V$ the volume in m³.
- **Bonello criterion** — bucket the modes into ⅓-octave bands; a good room's
  mode count per band never *decreases* as frequency rises. The app shows the
  bands as a bar chart and a pass/fail flag.
- **Room ratio** — dimensions normalized so the shortest = 1, compared to
  well-known good ratios (Sepmeyer, Louden, IEC/Bolt) with a deviation score.

---

## Speaker & listener placement

Knowing a room's modes is half the story; *where you put the speakers and the
listening seat* decides which of those modes you actually excite and hear. The
cuboid Viewer's **Speaker placement** panel models this. You drag a speaker (or
a stereo pair) and a listening position on a top-down plan, set their heights,
and the app re-derives what each placement does — all from the same analytical
mode shapes, so it stays live and offline. `lib/core/acoustics/`
(`speaker_placement.dart`, `room_response.dart`, `placement_advisor.dart`) with
Riverpod wiring in `lib/state/placement_providers.dart` and the UI in
`lib/ui/widgets/placement_panel.dart`.

### Mode excitation & audibility

A source drives mode $n$ in proportion to the mode shape **at the source**,
$\psi_n(\mathbf{r}_\text{src})$; what reaches the listener additionally scales
with the mode shape **at the listener**, $\psi_n(\mathbf{r}_\text{lis})$. Here
$\psi_n$ is exactly the cuboid pressure field from above. So per mode we report
two magnitudes in $[0, 1]$:

$$\text{source} = \bigl|\psi_n(\mathbf{r}_\text{src})\bigr|, \qquad \text{audibility} = \bigl|\psi_n(\mathbf{r}_\text{src})\,\psi_n(\mathbf{r}_\text{lis})\bigr|$$

The consequences are physical and immediate: a speaker sitting **on a mode's
nodal plane** ($\psi_n(\mathbf{r}_\text{src}) = 0$) cannot excite that mode at
any volume, and a listener on a nodal plane won't hear it even if it rings. A
toggle re-weights the Resonances axis by audibility, so the modes your placement
actually excites stand tall and the rest collapse to stubs. `modeExcitations` in
`speaker_placement.dart`.

### Stereo pairs & coherent summation

At low frequencies both speakers of a stereo pair play the same signal
**coherently**, so their contributions to a mode add **with sign** before
anything is heard:

$$\text{source} = \frac{1}{N}\left|\sum_{s=1}^{N} \psi_n(\mathbf{r}_s)\right|$$

The signs matter: a symmetric pair straddling the room's width centreline sits
at $+\psi$ and $-\psi$ on every **odd-order width mode** and cancels it exactly —
one of the reasons a symmetric setup sounds tighter. The app defaults to a
mirrored stereo pair (dragging one speaker moves both symmetrically) and offers
a **single-sub** mode for the subwoofer-placement question. Dividing by $N$
keeps mono and stereo levels comparable.

### Predicted frequency response

Beyond per-mode bars, the panel predicts the **steady-state frequency response
at the listener** by summing the damped modal contributions
(`computeRoomResponse` in `room_response.dart`):

$$p(f) = \sum_n \frac{\varepsilon_n\,\bigl[\sum_s \psi_n(\mathbf{r}_s)\bigr]\,\psi_n(\mathbf{r}_\text{lis})}{(f_n^2 - f^2) + j\,f f_n/Q_n}$$

- $\varepsilon_n = \prod (2 \text{ for each non-zero index})$ is the cosine-mode
  normalization $1/\Lambda_n$.
- Each mode is a damped resonator peaking at its own $f_n$; the imaginary term
  sets the width. The quality factor comes from the room's reverberation time,
  $Q_n \approx f_n \cdot \text{RT60} / 2.2$ (the standard
  $\text{RT60} = 2.2 / \Delta f_{3\text{dB}}$ relation), so a more reverberant
  room gives narrower, taller peaks.
- The lossless $(0,0,0)$ "pressure" term is added as its $-1/f^2$ limit, which
  produces the physical low-frequency **room gain** rise.
- Being a complex sum, terms **interfere**: this is what turns placement into
  audible peaks *and* deep nulls. The curve is normalized to a 0 dB mean —
  only its **shape** is meaningful — and a **flatness score** (the standard
  deviation of the dB curve, lower = flatter) summarizes it in one number. The
  response is **reciprocal**: swapping speaker and listener leaves it unchanged.

### The placement advisor

Because the response is reciprocal, the same machinery answers *"where should
the speakers go?"* and *"where should I sit?"* — only which endpoint is held
fixed differs. The advisor sweeps candidate positions across a grid over the
floor plan, computes the response flatness at each, and paints a **heatmap**
(cyan = flatter) with the single best spot ringed. In stereo mode it sweeps the
pair symmetrically. The sweep is `O(cells × freq-points × modes)`, so it runs
in a **background isolate** (debounced while you drag) and never blocks the UI.
`computeFlatnessGrid` / `bestSpot` in `placement_advisor.dart`,
`advisorGridProvider` in `placement_providers.dart`.

---

## Numerical solver for arbitrary rooms

This is the heart of the **Custom shape** workflow: how the app finds the modes
of a room that has *no* closed-form solution. Two solvers implement it, and it
matters which one runs:

| | **Native FEM** (primary) | **Dart FVM/FDM** (fallback + oracle) |
|---|---|---|
| Language | C++ (`native/`, via `dart:ffi`) | pure Dart (`lib/core/numeric/`) |
| Discretization | body-fitted **tetrahedral mesh**, P1 finite elements | staircased **voxel grid**, cell-centred finite volume |
| Eigen-solve | Lanczos on the generalized problem $K\mathbf{u}=\mu M\mathbf{u}$ | inverse iteration + Conjugate Gradient |
| When it runs | **Android** (what actually ships) | any build without the native lib — currently **iOS/desktop**, and every `flutter test` |

On a phone today the modes you see come from the **FEM** path — it is both
faster and more accurate on non-rectangular rooms, which is the whole point of
this workflow. The Dart path is a genuine fallback (it runs the moment the
native library is absent) *and* an independent reference the FEM tests check
against. Both solve the **same** physics with the **same** boundary condition;
they differ in how they discretize the geometry and which eigen-algorithm they
run. The section covers the shared physics, then each path.

### 1. The governing equation (both paths)

Sound pressure $p$ in a rigid-wall cavity $\Omega$ obeys the **Helmholtz
eigenproblem**

$$-\nabla^2 p = k^2 p \quad \text{in } \Omega, \qquad \frac{\partial p}{\partial n} = 0 \quad \text{on } \partial\Omega$$

$k = \omega/c = 2\pi f/c$ is the wavenumber. This is an eigenvalue problem: the
eigenvalues $\mu = k^2$ give the modal frequencies, the eigenfunctions $p$ the
mode shapes. The rigid-wall condition $\partial p/\partial n = 0$ (no normal air
velocity) is a **Neumann** boundary condition. Once an eigenvalue $\mu$ is in
hand, its frequency is

$$f = \frac{c\,\sqrt{\mu}}{2\pi}$$

using the temperature-dependent $c$ — the same conversion in both solvers
(`native/src/api/room_mode_solver.cpp` and
`lib/core/numeric/modal_analysis.dart`).

### 2. Native FEM path (what ships on Android)

`native/` (full writeup — including a real connected-components bug a 5-point
star test caught — in `native/README.md`):

1. **Triangulate & extrude.** The floor polygon is ear-clip triangulated,
   Delaunay-refined, uniformly subdivided, then extruded into a 3-D
   **tetrahedral mesh** (`polygon_tet_mesh.h`). Unlike voxels this is
   *body-fitted*: the mesh follows the actual walls instead of staircasing them.
2. **Assemble $K$ and $M$.** Standard P1 (linear) finite elements give a
   stiffness matrix $K$ (the discrete $-\nabla^2$) and a **lumped** (diagonal)
   mass matrix $M$ (`fem_assembly.h`). The Neumann condition is the natural
   boundary condition of the weak form — it needs no special handling.
3. **Solve the generalized eigenproblem.** We want the smallest eigenpairs of
   $K\mathbf{u} = \mu M\mathbf{u}$. Because $M$ is lumped/diagonal, this is
   symmetrized to a standard problem for $\tilde{K} = M^{-1/2} K M^{-1/2}$ (via
   `minvSqrt` $= 1/\sqrt{M_{ii}}$) and handed to a **Lanczos** iteration for the
   lowest modes (`fem_lanczos.h`).
4. **Boundary surface for free.** The mesh faces belonging to exactly one tet
   *are* the room's outer surface (walls/floor/ceiling); the solver returns them
   directly, with the field already sampled at those nodes — so the 3-D view
   needs no separate visualization grid or resampling.

The **resolution slider** maps to a mesh refinement level and extrusion-layer
count, calibrated so every slider position clears an accuracy floor (see the big
comment in `room_mode_solver.cpp`): the lowest setting keeps the box fundamental
to ~0.16 % and a concave L-room to ~0.9 %; the highest to ~0.04 %, at the cost
of a multi-second solve the UI warns about before running.

### 3. Dart FVM/FDM path (fallback + reference oracle)

When the native library isn't present, `lib/core/numeric/` solves the same
eigenproblem on a **voxel grid** instead of a mesh:

- **Voxelization** (`voxel_grid.dart`). The shape is diced into cubic cells of
  side $h$; a cell is "inside" when its centre is. Each inside cell stores the
  compact indices of its six axis neighbours, marking $-1$ where a neighbour is
  outside — **a missing neighbour is a wall**. The solver works purely off this
  connectivity, so it is shape-agnostic.
- **Discrete operator** (`laplacian_operator.dart`). $A = -\nabla^2$ is a
  cell-centred **finite-volume** stencil — which, on this uniform grid, is
  identical to the classic 7-point finite-difference Laplacian (hence "FVM/FDM"):

$$(A\mathbf{u})_i = \frac{1}{h^2}\sum_{j\,\in\,\mathcal{N}(i)} (u_i - u_j)$$

  Each face shared with an inside neighbour $j \in \mathcal{N}(i)$ contributes a
  $(u_i - u_j)/h^2$ flux; a face on a **wall has no neighbour and contributes
  nothing** — exactly $\partial p/\partial n = 0$. The rigid-wall condition
  falls out of the connectivity, no special-casing. $A$ is symmetric positive
  semi-definite, **matrix-free** (`apply(x)` just loops neighbours; no matrix is
  stored), and its null space is the constant vector — the trivial $\mu = 0$
  "DC" mode, which we skip by keeping every vector zero-mean.
- **Eigensolver** (`eigensolver.dart`) — **inverse iteration with deflation**:
  repeatedly solving $A\mathbf{w} = \mathbf{v}$ makes $\mathbf{w}$ converge to
  the smallest-eigenvalue eigenvector (because $A^{-1}$ amplifies small
  eigenvalues most); each inner solve is **Conjugate Gradient** (`cg_solver.dart`;
  a tiny shift keeps $A$ strictly positive). Vectors are kept zero-mean (skip
  DC) and Gram-Schmidt **deflated** against modes already found, so successive
  iterations land on the *next* mode up. Convergence is judged by the Rayleigh
  quotient $\mu = (\mathbf{u}^\top A\mathbf{u})/(\mathbf{u}^\top\mathbf{u})$ and
  the residual $\lVert A\mathbf{u} - \mu\mathbf{u}\rVert$; deterministic per seed.

**Why FVM here, FEM there.** The voxel path is trivial to run entirely in Dart
with no native toolchain, which is exactly what a fallback needs. Its cost is a
staircased boundary and $O(h^2)$ error; the body-fitted FEM represents slanted
walls more faithfully at a given resolution, which is why it's the primary path.
Validation: a 4×3×2 m box at resolution 12 ($h = \tfrac13$ m) matches the
analytical modes to within **3 %** (`test/numeric/box_modes_test.dart`); finer
grids are tighter. Cost scales steeply — cells $\sim$ resolution³ and CG
iterations grow with refinement — so resolution and mode count are both capped,
and the solve always runs off the UI thread (next).

### 4. Running off the UI thread (both paths)

A solve can take a noticeable fraction of a second (the native path more, at high
resolution), so it runs in a **background isolate** via Flutter's `compute()`
(`runFloorPlanAnalysis` in `lib/state/custom_room_providers.dart`). Editing the
floor plan is free; only the "Compute modes" button triggers a solve, so vertex
dragging never janks.

### 5. Visualization

A computed mode is a scalar field sampled at the nodes of the room's **boundary
surface mesh** (`RenderMesh` — either the native FEM solver's own boundary, or,
on the Dart fallback, the outward-facing voxel quads). The Viewer renders it as
a **rotatable 3D surface** (`computed_mode_3d_view.dart`): the mesh is drawn with
`Canvas.drawVertices` and Gouraud-shaded by the per-node field value in the same
cyan → dark → pink gradient the cuboid views use — a hand-rolled orthographic
painter, no 3D engine, to keep the app small. Drag to orbit.

---

## Project layout

```
lib/
  core/
    acoustics/     analytical layer — modes, speed of sound, pressure, notes,
                   Schroeder, Bonello / room ratios, AND the placement math
                   (speaker_placement, room_response, placement_advisor)
    geometry/      RoomShape (box, extruded polygon) + voxelizer + render mesh
    numeric/       Neumann Laplacian, CG, eigensolver, modal analysis
                   (the Dart fallback path — see native/ for what ships)
  state/           Riverpod providers (room, custom room, placement, navigation)
  ui/
    screens/       root shell, Setup screen, Viewer screen, expanded floor plan
    widgets/       CustomPainter visualizations, floor-plan editor, placement
                   panel, audio-backed keyboard, room-quality card
  audio/           on-the-fly sine-tone synthesis
native/            C++ FEM/FDM solver, called via dart:ffi -- see native/README.md
android/  ios/     platform projects (committed, not regenerated -- android/
                   carries the CMake/NDK wiring that builds native/)
tool/              make_icon.py — regenerates the launcher-icon master art
test/
  acoustics/  geometry/  numeric/  state/  widgets/
                   unit + widget tests anchoring the maths and the gating logic
```

The `core/` layer is pure Dart with no Flutter/UI imports, so it is
unit-testable and shared by both room kinds.

## Developing

```bash
flutter pub get
flutter test
flutter analyze
flutter run
```

To work on the native solver directly (no Flutter/mobile toolchain needed):
see `native/README.md`.

## Testing

Unit tests anchor the maths to known values, for example:

- analytical cuboid frequencies for a 5×4×3 m room (f(1,0,0)=34.3 Hz, etc.),
- the **numerical solver reproduces the analytical box modes within 3 %**,
- Bonello band counting and criterion pass/fail, room-proportion normalization,
- voxelization/connectivity and floor-area (shoelace),
- **placement**: corner sources excite every mode; a source on a mode's nodal
  plane excites nothing; a symmetric stereo pair cancels odd-order width modes;
  the response is reciprocal in speaker/listener.

## CI & release artifacts

`.github/workflows/build.yml` has two jobs:

- **native-test** — builds and runs the native solver's own test suite
  standalone (`cmake && make && ctest`), independent of Flutter, as a fast
  correctness gate.
- **build** — installs the NDK version the Android build needs, runs
  `flutter analyze` and `flutter test`, and builds **release APKs split per
  ABI** (~8–12 MB each — real install size, including the compiled native
  solver), uploaded as workflow artifacts.

The Play Store **App Bundle** is built by a separate tag-triggered workflow
(`release.yml`) — see "Shipping to Google Play" below.

## Shipping to Google Play

The repo is release-ready on the code side; shipping needs a few one-time
account-side steps.

### Signing

Release builds sign with the **debug key unless** `android/key.properties`
exists (git-ignored). To create the upload keystore once:

```bash
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias upload
```

then write `android/key.properties`:

```properties
storeFile=upload-keystore.jks     # path relative to android/
storePassword=...
keyAlias=upload
keyPassword=...
```

`.github/workflows/release.yml` builds a **signed AAB on every `v*` tag**.
It needs these repository secrets: `UPLOAD_KEYSTORE_BASE64`
(`base64 -w0 upload-keystore.jks`), `KEYSTORE_PASSWORD`, `KEY_ALIAS`,
`KEY_PASSWORD`.

### Pricing

The app is a **paid, one-time-purchase app** (no ads, no in-app purchases,
no data collection) — the price is set entirely in Play Console, not in
code. Set it there when promoting the first build to production.

Play Store policy does not allow flipping a live production release from
free to paid, only the reverse — so the price must be decided *before* the
first production release. This is not a blocker for a free pre-launch: app
installs distributed via Play Console's **testing tracks** (internal,
closed, open) are always free for testers regardless of the eventual
listing price, since testing tracks are not a "release" in the policy
sense. Run closed/open testing to gather feedback and reviews, then set
the real price only when promoting the tested build to production.

The launcher icon set regenerates from `assets/icon/` via
`dart run flutter_launcher_icons`; the master art comes from
`tool/make_icon.py`.

### Play Console checklist (account side)

1. Developer account; **personal accounts must run a 14-day closed test with
   12 testers before production** — start this first (this also serves as
   the free pre-launch phase, see "Pricing" above).
2. Store listing: title, descriptions, ≥2 screenshots, 1024×500 feature
   graphic.
3. **Privacy policy URL** + Data safety form (declare no data collected).
4. Content rating questionnaire; target audience is general/all ages (no
   ads, no data collection).
5. Set the app price, then upload the tagged AAB from the release workflow,
   roll out to the closed track, then production.

## Roadmap

Done: analytical cuboid calculator, room-quality metrics, on-device numerical
solver for arbitrary rooms (native FEM, with a Dart FDM fallback), rotatable 3D
mode-shape visualization, floor-plan editor, speaker/listener placement with
stereo-pair modeling and a flatness advisor, the Studio-themed Setup/Viewer
flow, and Play-release scaffolding (signing, icon, paid-app listing).

Possible next steps: finish the iOS native wiring (see `native/README.md`),
placement for custom (non-cuboid) rooms (needs interior field sampling from the
solver), parametric-EQ suggestions and an audible "hear your room" audition,
isosurface / volumetric 3D rendering, saving/loading rooms, and result export.
