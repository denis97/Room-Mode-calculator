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
  - [The governing equation](#1-the-governing-equation)
  - [Voxelization](#2-voxelization)
  - [The discrete operator (finite volume)](#3-the-discrete-operator-finite-volume)
  - [From eigenvalue to frequency](#4-from-eigenvalue-to-frequency)
  - [The eigensolver](#5-the-eigensolver)
  - [FDM vs FEM](#6-fdm-vs-fem)
  - [Accuracy, resolution & mode count](#7-accuracy-resolution--mode-count)
  - [Running off the UI thread](#8-running-off-the-ui-thread)
  - [Visualization](#9-visualization)
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

For a rigid-wall rectangular room `L × W × H` (metres) the modal frequencies
have a closed form:

```
f(p, q, r) = (c / 2) · √( (p/L)² + (q/W)² + (r/H)² )
```

with integer indices `p, q, r ∈ {0, 1, 2, …}` (not all zero) and `c` the speed
of sound. The solver enumerates every `(p, q, r)` up to the chosen cutoff — the
index bound per axis is `n ≤ 2·f_max·L / c` — and sorts by frequency.
Implemented in `lib/core/acoustics/mode_calculator.dart`.

### Speed of sound

Temperature-dependent, in dry air:

```
c = 331.3 · √(1 + T / 273.15)   m/s        (≈ 343 m/s at 20 °C)
```

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

The normalized standing-pressure field of mode `(p, q, r)` is a product of
cosines:

```
P(x, y, z) = cos(pπx/L) · cos(qπy/W) · cos(rπz/H)          (∈ [-1, 1])
```

Antinodes (|P| = 1) sit at the walls; nodal planes (P = 0) are where any cosine
crosses zero. `lib/core/acoustics/pressure_field.dart` samples this onto a grid
for the heatmaps and the 3D view.

### Note mapping

To place modes on a keyboard and let you hear them, frequencies map to MIDI /
musical pitch:

```
midi = 69 + 12·log₂(f / 440)        (A4 = 440 Hz = MIDI 69)
```

`lib/core/acoustics/note_mapping.dart`.

### Room-quality metrics

`lib/core/acoustics/schroeder.dart` and `room_ratios.dart`:

- **Schroeder frequency** — boundary between the modal region (discrete modes)
  and the diffuse region (dense overlap): `f_s = 2000·√(RT60 / V)`, `V` the
  volume in m³.
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

A source drives mode *n* in proportion to the mode shape **at the source**,
`ψₙ(src)`; what reaches the listener additionally scales with the mode shape
**at the listener**, `ψₙ(lis)`. Here `ψₙ` is exactly the cuboid pressure field
from above. So per mode we report two magnitudes in `[0, 1]`:

```
source     = | ψₙ(speaker) |                     — how hard the speaker drives it
audibility = | ψₙ(speaker) · ψₙ(listener) |      — how strongly it is heard
```

The consequences are physical and immediate: a speaker sitting **on a mode's
nodal plane** (`ψₙ(src) = 0`) cannot excite that mode at any volume, and a
listener on a nodal plane won't hear it even if it rings. A toggle re-weights
the Resonances axis by `audibility`, so the modes your placement actually
excites stand tall and the rest collapse to stubs. `modeExcitations` in
`speaker_placement.dart`.

### Stereo pairs & coherent summation

At low frequencies both speakers of a stereo pair play the same signal
**coherently**, so their contributions to a mode add **with sign** before
anything is heard:

```
source = | Σₛ ψₙ(srcₛ) | / N        (N = number of sources)
```

The signs matter: a symmetric pair straddling the room's width centreline sits
at `+ψ` and `−ψ` on every **odd-order width mode** and cancels it exactly — one
of the reasons a symmetric setup sounds tighter. The app defaults to a mirrored
stereo pair (dragging one speaker moves both symmetrically) and offers a
**single-sub** mode for the subwoofer-placement question. Dividing by `N` keeps
mono and stereo levels comparable.

### Predicted frequency response

Beyond per-mode bars, the panel predicts the **steady-state frequency response
at the listener** by summing the damped modal contributions
(`computeRoomResponse` in `room_response.dart`):

```
              εₙ · [ Σₛ ψₙ(srcₛ) ] · ψₙ(lis)
p(f) = Σₙ  ─────────────────────────────────────      (a complex sum)
              (fₙ² − f²) + j · f · fₙ / Qₙ
```

- `εₙ = ∏(2 for each non-zero index)` is the cosine-mode normalization `1/Λₙ`.
- Each mode is a damped resonator peaking at its own `fₙ`; the imaginary term
  sets the width. The quality factor comes from the room's reverberation time,
  `Qₙ ≈ fₙ · RT60 / 2.2` (the standard `RT60 = 2.2 / Δf₃dB` relation), so a more
  reverberant room gives narrower, taller peaks.
- The lossless `(0,0,0)` "pressure" term is added as its `−1/f²` limit, which
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

This is the heart of the "Custom 3D" tab: how the app finds the modes of a room
that has *no* closed-form solution.

**What actually ships:** a native FEM solver (C++, in `native/`, called via
`dart:ffi` — see `native/README.md` for the full writeup, including a real bug
a 5-point star test case caught and fixed). It's both faster and more accurate
than the pure-Dart path below on non-rectangular rooms, which is the whole
point of this tab. **The rest of this section documents the pure-Dart
finite-difference (FDM) solver** (`lib/core/numeric/`), which remains as the
automatic fallback (see `runFloorPlanAnalysis` in
`lib/state/custom_room_providers.dart`) and as an independent reference
implementation the native solver's tests check against. The physics and the
overall approach (voxelize → matrix-free operator → Lanczos/inverse-iteration
eigensolver) are the same story either way; only the discretization and
language differ.

It solves the acoustic eigenproblem **numerically on a voxel grid using a
finite-difference method (FDM)**. amroc pro solves the same physics with FEM;
the maths of the problem is identical, the discretization differs (see
[FDM vs FEM](#6-fdm-vs-fem)).

### 1. The governing equation

Sound pressure `p` in a rigid-wall cavity obeys the **Helmholtz eigenproblem**

```
−∇²p = k²p           inside the room
∂p/∂n = 0            on the walls   (rigid wall = no normal air velocity)
```

`k = ω/c = 2πf/c` is the wavenumber. Solving this is an eigenvalue problem: the
eigenvalues `μ = k²` give the modal frequencies, the eigenfunctions `p` give the
mode shapes. The rigid-wall condition `∂p/∂n = 0` is a **Neumann** boundary
condition.

### 2. Voxelization

The room shape (`RoomShape` — a `BoxShape`, or an `ExtrudedPolygonShape` built
from your floor polygon extruded to a height) is diced into a regular grid of
**cubic cells** of side `h`. A cell belongs to the room when its **centre** is
inside the shape. Each inside cell gets a compact index; for each one we
precompute the compact indices of its six axis neighbours, marking `−1` where a
neighbour is outside — i.e. **a missing neighbour is a wall**. The solver then
works purely off this connectivity, so it is completely shape-agnostic.
`lib/core/geometry/voxel_grid.dart`.

### 3. The discrete operator (finite volume)

We need a discrete version of `A = −∇²` with the Neumann condition baked in. Use
a **cell-centred finite-volume** stencil: for cell *i*,

```
(A·u)_i = (1/h²) · Σ_{j ∈ inside-neighbours(i)} (u_i − u_j)
```

That is: each face shared with an *inside* neighbour contributes a
`(u_i − u_j)/h²` flux; a face on a **wall has no neighbour and contributes
nothing** — which is exactly zero normal flux, `∂p/∂n = 0`. So the rigid-wall
condition falls out of the connectivity for free, with no special-casing.

Key properties of `A` (all used by the solver):

- **Symmetric** and **positive semi-definite**.
- Its **null space is the constant vector** — the trivial `μ = 0` "DC" mode at
  0 Hz. Physically that is the uniform-pressure non-mode; we skip it.
- `A·u` always has **zero sum**, so `A` maps the zero-mean subspace to itself.
  Conjugate Gradient started from zero therefore stays orthogonal to the null
  space automatically.

The operator is **matrix-free** — `apply(x)` just loops cells and their six
neighbours; we never store a matrix. `lib/core/numeric/laplacian_operator.dart`.

### 4. From eigenvalue to frequency

An eigenpair `(μ, u)` of `A` is a mode. Since `μ = k² = (2πf/c)²`,

```
f = c · √μ / (2π)
```

`lib/core/numeric/modal_analysis.dart` does this conversion using the
temperature-dependent `c`.

### 5. The eigensolver

We want the **few smallest non-zero** eigenvalues (the lowest modes). The app
uses **inverse iteration with deflation** (`lib/core/numeric/eigensolver.dart`):

1. **Inverse iteration.** Repeatedly solving `A·w = v` and renormalising makes
   `w` converge to the eigenvector with the *smallest* eigenvalue, because
   `A⁻¹` amplifies small-eigenvalue components the most.
2. **Inner solve = Conjugate Gradient.** Each `A·w = v` is solved with CG
   (`cg_solver.dart`). `A` is symmetric positive-(semi)definite and matrix-free,
   which is exactly what CG wants; a tiny shift keeps it strictly positive for
   robustness.
3. **Skip the DC mode.** We keep every vector **zero-mean**, projecting out the
   constant null space, so the iteration converges to the smallest *non-zero*
   eigenvalue rather than the trivial 0.
4. **Deflation for the next modes.** After finding a mode, subsequent iterations
   are orthogonalised (Gram-Schmidt) against all modes found so far, so the
   iteration lands on the *next* mode up instead of re-finding the same one.
5. **Convergence** is judged by the Rayleigh quotient `μ = (uᵀAu)/(uᵀu)` and the
   residual `‖A·u − μ·u‖`. The whole process is deterministic for a given seed.

### 6. FDM vs FEM

amroc pro uses the **Finite Element Method**: it meshes the room into
tetrahedra and expands the field in basis functions, assembling stiffness `K`
and mass `M` matrices and solving `K·u = μ·M·u`.

This app uses the **Finite Difference / Finite Volume Method** on a regular
voxel grid instead. It solves the *same* Helmholtz eigenproblem with the *same*
Neumann boundary condition, but:

- the geometry is approximated by voxels (a staircased boundary) rather than a
  body-fitted mesh,
- the operator is a simple matrix-free stencil rather than an assembled `K`/`M`.

FDM is much simpler to implement and run **entirely on a phone**, and for the
low modes that dominate room acoustics it agrees with the analytical cuboid
solution to within the discretization error (see below). A body-fitted FEM
would represent slanted/curved walls more faithfully at a given resolution; that
is a possible future upgrade.

### 7. Accuracy, resolution & mode count

Two controls trade accuracy for speed:

- **Resolution** = cells along the longest axis, so `h = longest_dim /
  resolution`. The finite-difference error is **O(h²)**, and coarse grids read
  modes slightly **low**. The grid also rounds each dimension to a multiple of
  `h`, and approximates the boundary as a staircase — both improve as `h`
  shrinks. Validation: a 4×3×2 m box at resolution 12 matches the analytical
  modes to within **3 %**; higher resolutions are tighter. **Cost scales
  steeply** (cells ~ resolution³, and CG iterations grow as the grid refines, so
  total work ~ resolution⁴–⁵) — which is why resolution is capped and the solve
  runs off the UI thread.
- **Mode count.** Modes are found one at a time and each is deflated against all
  previous ones, so cost grows faster than linearly; higher modes are also
  closer together (slower, less reliable convergence) and need enough cells per
  wavelength to be represented at all. Hence a deliberate cap rather than an
  unbounded list. The UI shows the live cell size and grid dimensions so the
  trade-off is visible while you drag.

### 8. Running off the UI thread

A solve can take a noticeable fraction of a second, so it runs in a **background
isolate** via Flutter's `compute()` (`runFloorPlanAnalysis` in
`lib/state/custom_room_providers.dart`). Editing the floor plan is free; only
the "Compute modes" button triggers a solve, so vertex dragging never janks.

### 9. Visualization

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
  monetization/    ads (banner + capped interstitial, UMP consent) and the
                   one-time Pro (remove-ads) in-app purchase
native/            C++ FEM/FDM solver, called via dart:ffi -- see native/README.md
android/  ios/     platform projects (committed, not regenerated -- android/
                   carries the CMake/NDK wiring that builds native/)
tool/              make_icon.py — regenerates the launcher-icon master art
test/
  acoustics/  geometry/  numeric/  state/  widgets/  monetization/
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
  the response is reciprocal in speaker/listener,
- **monetization gating**: ads stay off under `flutter test`, Pro disables ads,
  and the interstitial frequency cap holds.

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
`KEY_PASSWORD`, and optionally `ADMOB_APP_ID`.

### Monetization wiring

One free app: ads for everyone, a one-time **`pro_no_ads`** in-app product
removes them (`lib/monetization/`). Ads only appear as a banner inside the
custom-solve wait overlay and as a frequency-capped interstitial (max 3 per
session, ≥3 min apart) when opening the viewer. GDPR consent runs through
Google UMP before ad init.

Every checkout builds with **Google's test ad IDs** — safe by construction.
Production IDs are injected at release time only:

- AdMob **app ID** → `ADMOB_APP_ID` secret (manifest placeholder),
- ad **unit IDs** → `--dart-define=ADMOB_BANNER_UNIT=…` /
  `ADMOB_INTERSTITIAL_UNIT=…`,
- the `pro_no_ads` product must be created in Play Console → Monetize →
  In-app products (price ~€3–5), matching `kProProductId`.

The launcher icon set regenerates from `assets/icon/` via
`dart run flutter_launcher_icons`; the master art comes from
`tool/make_icon.py`.

### Play Console checklist (account side)

1. Developer account; **personal accounts must run a 14-day closed test with
   12 testers before production** — start this first.
2. Store listing: title, descriptions, ≥2 screenshots, 1024×500 feature
   graphic.
3. **Privacy policy URL** (required with AdMob) + Data safety form
   (declares ad-related device identifiers).
4. Content rating questionnaire; target audience 13+ (ads must not be
   child-directed).
5. Upload the tagged AAB from the release workflow, roll out to the closed
   track, then production.

## Roadmap

Done: analytical cuboid calculator, room-quality metrics, on-device numerical
solver for arbitrary rooms (native FEM, with a Dart FDM fallback), rotatable 3D
mode-shape visualization, floor-plan editor, speaker/listener placement with
stereo-pair modeling and a flatness advisor, the Studio-themed Setup/Viewer
flow, and Play-release scaffolding (signing, icon, ads + Pro unlock).

Possible next steps: finish the iOS native wiring (see `native/README.md`),
placement for custom (non-cuboid) rooms (needs interior field sampling from the
solver), parametric-EQ suggestions and an audible "hear your room" audition,
isosurface / volumetric 3D rendering, saving/loading rooms, and result export.
