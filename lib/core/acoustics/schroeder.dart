import 'dart:math' as math;

import 'room.dart';

/// The Schroeder frequency marks the transition between the modal region (below)
/// and the diffuse/statistical region (above), where individual room modes give
/// way to a dense overlap of resonances.
///
///     f_schroeder = 2000 · √(RT60 / V)
///
/// with RT60 in seconds and volume V in cubic metres.
double schroederFrequency(Room room) {
  if (room.volume <= 0) return 0;
  return 2000 * math.sqrt(room.rt60Seconds / room.volume);
}
