import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/acoustics/mode.dart';
import '../core/acoustics/mode_calculator.dart';
import '../core/acoustics/room.dart';
import '../core/acoustics/schroeder.dart';
import '../core/constants.dart';

/// The current room and ambient settings. The UI edits this; everything else
/// derives from it.
final roomProvider = StateProvider<Room>((ref) => const Room());

/// The highest modal frequency to enumerate (Hz). Adjustable from the UI.
final maxFrequencyProvider =
    StateProvider<double>((ref) => AcousticDefaults.maxFrequencyHz);

/// The calculated modes, recomputed whenever the room or cutoff changes.
final modesProvider = Provider<List<RoomMode>>((ref) {
  final room = ref.watch(roomProvider);
  final maxFreq = ref.watch(maxFrequencyProvider);
  return calculateRoomModes(room, maxFrequencyHz: maxFreq);
});

/// The Schroeder frequency for the current room.
final schroederProvider = Provider<double>((ref) {
  final room = ref.watch(roomProvider);
  return schroederFrequency(room);
});

/// The index (into [modesProvider]) of the mode currently selected for the
/// pressure map, or null if none is selected.
final selectedModeIndexProvider = StateProvider<int?>((ref) => null);

/// The height of the horizontal slice used by the pressure map, in metres.
final sliceHeightProvider =
    StateProvider<double>((ref) => AcousticDefaults.earHeightM);
