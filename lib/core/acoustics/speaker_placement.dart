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

/// Mirrors a placement across the room's width centerline — how a stereo
/// pair relates: the right speaker is the left one reflected in y.
PlacementPoint mirrorAcrossWidth(PlacementPoint p) =>
    PlacementPoint(fx: p.fx, fy: 1 - p.fy, fz: p.fz);

/// How strongly a set of speakers plus a listener couple to a single mode.
///
/// Each source drives mode n in proportion to the mode shape at its
/// position, ψₙ(source); a multi-speaker setup plays the same low-frequency
/// signal from every cabinet, so the couplings add *with sign* before
/// anything is heard — a symmetric stereo pair sits at ±ψ on every
/// odd-order width mode and cancels it entirely. What arrives at the
/// listener additionally scales with ψₙ(listener). Both values are
/// normalized magnitudes in [0, 1].
class ModeExcitation {
  const ModeExcitation({required this.source, required this.audibility});

  /// |Σ ψ(speakerᵢ)| / n — how strongly the speakers jointly drive the mode.
  final double source;

  /// |Σ ψ(speakerᵢ) · ψ(listener)| / n — how strongly the mode is heard.
  final double audibility;
}

/// Per-mode excitation for the given speakers and listener placements,
/// aligned index-for-index with [modes].
List<ModeExcitation> modeExcitations(
  List<RoomMode> modes,
  Room room,
  List<PlacementPoint> speakers,
  PlacementPoint listener,
) {
  if (speakers.isEmpty) {
    return List.filled(
        modes.length, const ModeExcitation(source: 0, audibility: 0));
  }
  final lx = listener.x(room), ly = listener.y(room), lz = listener.z(room);
  return [
    for (final mode in modes)
      () {
        var sum = 0.0;
        for (final s in speakers) {
          sum += pressureAt(mode, room,
              x: s.x(room), y: s.y(room), z: s.z(room));
        }
        final source = sum.abs() / speakers.length;
        final atListener = pressureAt(mode, room, x: lx, y: ly, z: lz);
        return ModeExcitation(
          source: source,
          audibility: source * atListener.abs(),
        );
      }(),
  ];
}
