# Room Mode Calculator

A Flutter app (Android first, iOS later) that calculates the **acoustic room
modes** of a rectangular room — the standing-wave resonances that colour the
low-frequency sound of any room. It's inspired by
[amroc](https://amcoustics.com/tools/amroc/) by amcoustics.

## What it does (Phase 1 — cuboid calculator)

Enter the room's length, width, height, air temperature and reverberation time,
and the app computes every room mode up to a chosen frequency and shows it as:

- **Frequency axis** — modes plotted on a frequency line, coloured by type and
  sized by strength, with the Schroeder frequency marked.
- **Piano keyboard** — modes marked on the keys they match; tap a key to hear
  the pitch.
- **2D pressure map** — a top-down heatmap of the selected mode's standing
  pressure pattern, with an adjustable slice height (blue/red = pressure
  antinodes, dark = nodal lines).
- **Mode list** — every mode with its frequency, indices `(p,q,r)`, type
  (axial / tangential / oblique) and nearest musical note.

Everything recomputes live as you edit the inputs, and runs fully offline.

## The acoustics

Modal frequencies of a rigid-wall rectangular room:

```
f(p,q,r) = (c / 2) · √( (p/L)² + (q/W)² + (r/H)² )
```

where `c = 331.3 · √(1 + T/273.15)` m/s is the temperature-dependent speed of
sound and `L, W, H` are the room dimensions. Modes are classified by how many of
`p, q, r` are non-zero: one → **axial** (strongest), two → **tangential**,
three → **oblique** (weakest). The normalized pressure field of a mode is
`P(x,y,z) = cos(pπx/L)·cos(qπy/W)·cos(rπz/H)`.

## Project layout

```
lib/
  core/acoustics/   pure-Dart calculation layer (modes, pressure, notes, …)
  state/            Riverpod providers (room inputs → derived modes)
  ui/               screens + CustomPainter visualizations
  audio/            on-the-fly sine-tone synthesis (tone_player)
test/acoustics/     unit tests anchoring the math to known values
```

The calculation layer is deliberately UI-free so it can be reused by the planned
Phase 2 (arbitrary 3D geometry via on-device FEM).

## Developing

```bash
flutter create .    # regenerate the android/ ios/ platform folders
flutter pub get
flutter test        # runs the acoustics unit tests
flutter analyze
flutter run         # launch on a connected device / emulator
```

> The platform scaffolding (`android/`, `ios/`) is generated boilerplate and is
> recreated by `flutter create .` from this project's `pubspec.yaml`; only the
> Dart sources under `lib/` and `test/` carry the app's logic.

## Roadmap

- **Phase 1 (this build):** analytical cuboid calculator — modes, keyboard,
  pressure map, mode list.
- **Phase 1c (optional):** Bonello criterion, Bolt-area room-ratio quality.
- **Phase 2 (later):** arbitrary-shaped rooms via on-device Finite Element
  Method, with 3D mode-shape visualization.
