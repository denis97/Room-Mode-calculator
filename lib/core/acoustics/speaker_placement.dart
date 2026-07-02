import 'pressure_field.dart';
import 'mode.dart';
import 'room.dart';

/// Where a speaker or listener sits inside the room.
///
/// Coordinates are stored as fractions of the room dimensions (each in
/// [0, 1]) rather than metres, so a placement stays inside the room — and
/// keeps its intent, "a third of the way along the wall" — when the user
/// edits the dimensions.
class PlacementPoint {
  const PlacementPoint({
    required this.fx,
    required this.fy,
    required this.fz,
  });

  /// Fraction of the room length (x), width (y) and height (z), each 0..1.
  final double fx;
  final double fy;
  final double fz;

  double x(Room room) => fx * room.length;
  double y(Room room) => fy * room.width;
  double z(Room room) => fz * room.height;

  PlacementPoint copyWith({double? fx, double? fy, double? fz}) {
    return PlacementPoint(
      fx: (fx ?? this.fx).clamp(0.0, 1.0),
      fy: (fy ?? this.fy).clamp(0.0, 1.0),
      fz: (fz ?? this.fz).clamp(0.0, 1.0),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlacementPoint &&
      other.fx == fx &&
      other.fy == fy &&
      other.fz == fz;

  @override
  int get hashCode => Object.hash(fx, fy, fz);
}

/// How strongly one speaker/listener pair couples to a single mode.
///
/// A source drives mode n in proportion to the mode shape at the source
/// position, ψₙ(source); what arrives at the listener additionally scales
/// with ψₙ(listener). Both values are magnitudes in [0, 1]: a speaker on a
/// mode's nodal plane ([source] = 0) cannot excite it no matter how loud it
/// plays, and a listener on a nodal plane won't hear it even if it rings.
class ModeExcitation {
  const ModeExcitation({required this.source, required this.audibility});

  /// |ψ(speaker)| — how strongly the speaker drives the mode.
  final double source;

  /// |ψ(speaker) · ψ(listener)| — how strongly the mode is heard.
  final double audibility;
}

/// Per-mode excitation for the given speaker and listener placements,
/// aligned index-for-index with [modes].
List<ModeExcitation> modeExcitations(
  List<RoomMode> modes,
  Room room,
  PlacementPoint speaker,
  PlacementPoint listener,
) {
  final sx = speaker.x(room), sy = speaker.y(room), sz = speaker.z(room);
  final lx = listener.x(room), ly = listener.y(room), lz = listener.z(room);
  return [
    for (final mode in modes)
      _excitationFor(mode, room, sx, sy, sz, lx, ly, lz),
  ];
}

ModeExcitation _excitationFor(
  RoomMode mode,
  Room room,
  double sx,
  double sy,
  double sz,
  double lx,
  double ly,
  double lz,
) {
  final atSpeaker = pressureAt(mode, room, x: sx, y: sy, z: sz);
  final atListener = pressureAt(mode, room, x: lx, y: ly, z: lz);
  return ModeExcitation(
    source: atSpeaker.abs(),
    audibility: (atSpeaker * atListener).abs(),
  );
}
