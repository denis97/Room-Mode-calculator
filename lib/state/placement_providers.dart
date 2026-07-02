import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/acoustics/placement_advisor.dart';
import '../core/acoustics/room_response.dart';
import '../core/acoustics/speaker_placement.dart';
import 'room_providers.dart';

/// Speaker position, as fractions of the room dimensions. Defaults to a
/// typical stereo/sub spot: near the front wall, off-center, woofer height.
final speakerPosProvider = StateProvider<PlacementPoint>(
  (ref) => const PlacementPoint(fx: 0.12, fy: 0.3, fz: 0.15),
);

/// Listener position. Defaults to the studio "38% rule": ears 38% of the
/// room length from the front wall, centered in width, seated ear height.
final listenerPosProvider = StateProvider<PlacementPoint>(
  (ref) => const PlacementPoint(fx: 0.38, fy: 0.5, fz: 0.4),
);

/// Whether the main resonance axis re-weights its bars by how audible each
/// mode is from the current placement (toggled from the placement panel).
final placementWeightAxisProvider = StateProvider<bool>((ref) => false);

/// Per-mode excitation/audibility for the current room + placement, aligned
/// with [modesProvider].
final modeExcitationsProvider = Provider<List<ModeExcitation>>((ref) {
  final room = ref.watch(roomProvider);
  final modes = ref.watch(modesProvider);
  final speaker = ref.watch(speakerPosProvider);
  final listener = ref.watch(listenerPosProvider);
  return modeExcitations(modes, room, speaker, listener);
});

/// Predicted frequency response at the listener for the current placement.
final roomResponseProvider = Provider<ResponseCurve>((ref) {
  final room = ref.watch(roomProvider);
  final modes = ref.watch(modesProvider);
  final speaker = ref.watch(speakerPosProvider);
  final listener = ref.watch(listenerPosProvider);
  final maxHz = ref.watch(maxFrequencyProvider);
  return computeRoomResponse(modes, room, speaker, listener, maxHz: maxHz);
});

/// Which advisor heatmap (if any) is shown under the placement plan.
enum AdvisorMode {
  none,
  speaker,
  listener;

  String get label => switch (this) {
        AdvisorMode.none => 'Off',
        AdvisorMode.speaker => 'Speaker spots',
        AdvisorMode.listener => 'Listening spots',
      };
}

final advisorModeProvider = StateProvider<AdvisorMode>((ref) => AdvisorMode.none);

/// The advisor sweep for the current mode: a grid of flatness scores over
/// the floor plan, computed off the UI thread. Null when the advisor is off.
final advisorGridProvider = FutureProvider<FlatnessGrid?>((ref) async {
  final mode = ref.watch(advisorModeProvider);
  if (mode == AdvisorMode.none) return null;

  final room = ref.watch(roomProvider);
  final modes = ref.watch(modesProvider);
  final maxHz = ref.watch(maxFrequencyProvider);

  // Only the *fixed* endpoint and the sweep height matter; deliberately not
  // watching the moving endpoint's x/y, so dragging the marker being advised
  // doesn't re-run the whole sweep on every frame.
  final movingIsSpeaker = mode == AdvisorMode.speaker;
  final fixed = movingIsSpeaker
      ? ref.watch(listenerPosProvider)
      : ref.watch(speakerPosProvider);
  final movingHeight = movingIsSpeaker
      ? ref.watch(speakerPosProvider.select((p) => p.fz))
      : ref.watch(listenerPosProvider.select((p) => p.fz));

  final request = AdvisorRequest(
    room: room,
    modes: modes,
    fixed: fixed,
    movingHeightFraction: movingHeight,
    maxHz: maxHz,
  );

  // Debounce: dragging the fixed endpoint invalidates this provider every
  // frame; wait out the burst so only the settled position pays for an
  // isolate sweep.
  var alive = true;
  ref.onDispose(() => alive = false);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  if (!alive) return null;

  return compute(computeFlatnessGrid, request);
});
