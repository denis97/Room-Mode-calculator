import 'dart:math' as math;

import 'room.dart';

/// Room-quality metrics: the Bonello criterion (modal density across
/// ⅓-octave bands) and room-proportion analysis against recommended ratios.
/// These judge whether a room's dimensions give a smooth low-frequency
/// response — the same tools amroc surfaces.

/// One ⅓-octave band with the number of modes that fall inside it.
class ThirdOctaveBand {
  const ThirdOctaveBand({
    required this.centerHz,
    required this.lowHz,
    required this.highHz,
    required this.modeCount,
  });

  final double centerHz;
  final double lowHz;
  final double highHz;
  final int modeCount;
}

/// The ⅓-octave band index for a frequency, relative to the 1 kHz reference.
int _bandIndex(double f) => (3 * math.log(f / 1000) / math.ln2).round();

double _bandCenter(int n) => 1000 * math.pow(2, n / 3).toDouble();

/// Buckets [frequencies] into the ⅓-octave bands spanning [minHz]..[maxHz] and
/// counts the modes in each — the data behind the Bonello criterion.
List<ThirdOctaveBand> bonelloBands(
  List<double> frequencies, {
  double minHz = 16,
  double maxHz = 200,
}) {
  if (maxHz <= minHz) return const [];
  final nLow = _bandIndex(minHz);
  final nHigh = _bandIndex(maxHz);
  final ratio = math.pow(2, 1 / 6).toDouble(); // half a ⅓-octave

  final bands = <ThirdOctaveBand>[];
  for (var n = nLow; n <= nHigh; n++) {
    final center = _bandCenter(n);
    final low = center / ratio;
    final high = center * ratio;
    var count = 0;
    for (final f in frequencies) {
      if (f >= low && f < high) count++;
    }
    bands.add(ThirdOctaveBand(
      centerHz: center,
      lowHz: low,
      highHz: high,
      modeCount: count,
    ));
  }
  return bands;
}

/// The Bonello criterion: from the first populated band upward, the mode count
/// per ⅓-octave should never decrease. A monotonically rising density means no
/// band is starved of modes relative to a lower one.
bool bonelloSatisfied(List<ThirdOctaveBand> bands) {
  var started = false;
  var previous = 0;
  for (final band in bands) {
    if (!started) {
      if (band.modeCount == 0) continue;
      started = true;
      previous = band.modeCount;
      continue;
    }
    if (band.modeCount < previous) return false;
    previous = band.modeCount;
  }
  return started;
}

/// A room's dimensions normalized so the shortest is 1, sorted ascending —
/// the form used to compare against recommended ratios.
class RoomProportion {
  const RoomProportion(this.short, this.mid, this.long);

  /// Always 1.0 (the shortest dimension).
  final double short;
  final double mid;
  final double long;

  factory RoomProportion.fromRoom(Room room) {
    final dims = [room.length, room.width, room.height]..sort();
    final s = dims[0];
    if (s <= 0) return const RoomProportion(1, 1, 1);
    return RoomProportion(1, dims[1] / s, dims[2] / s);
  }

  @override
  String toString() =>
      '1 : ${mid.toStringAsFixed(2)} : ${long.toStringAsFixed(2)}';
}

/// A named recommended room ratio (shortest normalized to 1).
class RecommendedRatio {
  const RecommendedRatio(this.name, this.mid, this.long);
  final String name;
  final double mid;
  final double long;
}

/// Well-known "good" room ratios from the literature.
const List<RecommendedRatio> recommendedRatios = [
  RecommendedRatio('Sepmeyer A', 1.14, 1.39),
  RecommendedRatio('Sepmeyer B', 1.28, 1.54),
  RecommendedRatio('Louden', 1.4, 1.9),
  RecommendedRatio('Sepmeyer C', 1.6, 2.33),
  RecommendedRatio('IEC / Bolt', 1.5, 2.5),
];

/// The recommended ratio closest to [proportion] (Euclidean distance in the
/// mid/long plane), with that distance — a simple "how good are my
/// proportions?" indicator.
(RecommendedRatio, double) nearestRecommendedRatio(RoomProportion proportion) {
  var best = recommendedRatios.first;
  var bestDist = double.infinity;
  for (final r in recommendedRatios) {
    final dm = r.mid - proportion.mid;
    final dl = r.long - proportion.long;
    final d = math.sqrt(dm * dm + dl * dl);
    if (d < bestDist) {
      bestDist = d;
      best = r;
    }
  }
  return (best, bestDist);
}
