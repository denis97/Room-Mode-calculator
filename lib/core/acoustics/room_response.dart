import 'dart:math' as math;
import 'dart:typed_data';

import 'mode.dart';
import 'pressure_field.dart';
import 'room.dart';
import 'speaker_placement.dart';

/// Predicted steady-state frequency response at a listener position, from a
/// speaker position, via modal summation over the rigid-wall modes:
///
///     p(f) = Σₙ εₙ · ψₙ(src) · ψₙ(lis) / ((fₙ² − f²) + j·f·fₙ/Qₙ)
///
/// where ψₙ is the mode shape, εₙ = ∏(2 for each non-zero index) is the
/// modal normalization (1/Λₙ for cosine modes), and the quality factor
/// follows from the room's reverberation time, Qₙ ≈ fₙ·RT60 / 2.2 — the
/// familiar RT60 = 2.2/Δf₃dB relation. The (0,0,0) "pressure" mode is
/// included as its lossless −1/f² limit, which produces the physical rise
/// toward very low frequencies (room gain).
///
/// The absolute level of a modal sum is arbitrary, so [ResponseCurve.db] is
/// normalized to a 0 dB mean; what matters is the *shape* — the peaks and
/// nulls placement creates.
class ResponseCurve {
  const ResponseCurve({required this.frequencies, required this.db});

  final Float64List frequencies;

  /// Relative magnitude in dB (mean-normalized), one per frequency.
  final Float64List db;

  bool get isEmpty => frequencies.isEmpty;

  /// Standard deviation of [db] — the flatness score (lower is flatter).
  double get flatness {
    if (db.isEmpty) return 0;
    var mean = 0.0;
    for (final v in db) {
      mean += v;
    }
    mean /= db.length;
    var sq = 0.0;
    for (final v in db) {
      sq += (v - mean) * (v - mean);
    }
    return math.sqrt(sq / db.length);
  }
}

/// Computes the response curve for [modes] between [minHz] and [maxHz],
/// sampled at [points] evenly spaced frequencies.
ResponseCurve computeRoomResponse(
  List<RoomMode> modes,
  Room room,
  PlacementPoint speaker,
  PlacementPoint listener, {
  double minHz = 20,
  required double maxHz,
  int points = 240,
}) {
  if (modes.isEmpty || maxHz <= minHz || points < 2) {
    return ResponseCurve(
      frequencies: Float64List(0),
      db: Float64List(0),
    );
  }

  final coupling = _modeCoupling(modes, room, speaker, listener);
  final freqs = Float64List(points);
  final db = Float64List(points);

  final rt60 = math.max(room.rt60Seconds, 0.05);
  for (var i = 0; i < points; i++) {
    final f = minHz + (maxHz - minHz) * i / (points - 1);
    freqs[i] = f;
    // Lossless (0,0,0) term: ε=1, ψ=1, fₙ=0 → 1/(0 − f²).
    var re = -1.0 / (f * f);
    var im = 0.0;
    for (var n = 0; n < modes.length; n++) {
      final fn = modes[n].frequency;
      final q = fn * rt60 / 2.2;
      final dRe = fn * fn - f * f;
      final dIm = f * fn / q;
      final mag2 = dRe * dRe + dIm * dIm;
      // coupling / (dRe + j·dIm)
      re += coupling[n] * dRe / mag2;
      im += coupling[n] * -dIm / mag2;
    }
    db[i] = 10 * _log10(re * re + im * im);
  }

  // Normalize to 0 dB mean: only the curve's shape is meaningful.
  var mean = 0.0;
  for (final v in db) {
    mean += v;
  }
  mean /= points;
  for (var i = 0; i < points; i++) {
    db[i] -= mean;
  }

  return ResponseCurve(frequencies: freqs, db: db);
}

/// Signed coupling εₙ·ψₙ(src)·ψₙ(lis) for each mode. The sign matters:
/// terms interfere, which is exactly how placement creates nulls.
Float64List _modeCoupling(
  List<RoomMode> modes,
  Room room,
  PlacementPoint speaker,
  PlacementPoint listener,
) {
  final sx = speaker.x(room), sy = speaker.y(room), sz = speaker.z(room);
  final lx = listener.x(room), ly = listener.y(room), lz = listener.z(room);
  final coupling = Float64List(modes.length);
  for (var n = 0; n < modes.length; n++) {
    final mode = modes[n];
    final eps = (mode.p != 0 ? 2.0 : 1.0) *
        (mode.q != 0 ? 2.0 : 1.0) *
        (mode.r != 0 ? 2.0 : 1.0);
    coupling[n] = eps *
        pressureAt(mode, room, x: sx, y: sy, z: sz) *
        pressureAt(mode, room, x: lx, y: ly, z: lz);
  }
  return coupling;
}

double _log10(double v) => math.log(math.max(v, 1e-30)) / math.ln10;
