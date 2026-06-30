import 'dart:math' as math;

import '../constants.dart';
import 'mode.dart';
import 'room.dart';
import 'speed_of_sound.dart';

/// Calculates the room modes of a rigid-wall rectangular room.
///
/// The modal frequency of mode (p, q, r) is
///
///     f(p,q,r) = (c / 2) · √( (p/L)² + (q/W)² + (r/H)² )
///
/// where `c` is the speed of sound and L, W, H are the room dimensions. This
/// enumerates every index combination whose frequency is at or below
/// [maxFrequencyHz] and returns the modes sorted by ascending frequency.
List<RoomMode> calculateRoomModes(
  Room room, {
  double maxFrequencyHz = AcousticDefaults.maxFrequencyHz,
}) {
  final c = speedOfSound(temperatureC: room.temperatureC);

  // For each axis the highest useful index is bounded by the axial mode that
  // still falls at or below the cutoff: f(n,0,0) = c·n / (2·L) ≤ fmax.
  final maxP = (2 * maxFrequencyHz * room.length / c).floor();
  final maxQ = (2 * maxFrequencyHz * room.width / c).floor();
  final maxR = (2 * maxFrequencyHz * room.height / c).floor();

  final modes = <RoomMode>[];
  for (var p = 0; p <= maxP; p++) {
    final tp = p / room.length;
    for (var q = 0; q <= maxQ; q++) {
      final tq = q / room.width;
      for (var r = 0; r <= maxR; r++) {
        if (p == 0 && q == 0 && r == 0) continue; // (0,0,0) is not a mode
        final tr = r / room.height;
        final frequency =
            (c / 2) * math.sqrt(tp * tp + tq * tq + tr * tr);
        if (frequency <= maxFrequencyHz) {
          modes.add(RoomMode(p: p, q: q, r: r, frequency: frequency));
        }
      }
    }
  }

  modes.sort((a, b) => a.frequency.compareTo(b.frequency));
  return modes;
}
