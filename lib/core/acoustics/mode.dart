/// Classification of a room mode by how many of its indices are non-zero.
///
/// Axial modes (one non-zero index) are the strongest and most audible,
/// tangential modes (two) are weaker, and oblique modes (three) weakest.
enum ModeType {
  axial,
  tangential,
  oblique;

  /// Relative excitation/strength weighting, axial : tangential : oblique
  /// = 4 : 2 : 1. Used to size markers and rank modes by importance.
  double get strength => switch (this) {
        ModeType.axial => 4.0,
        ModeType.tangential => 2.0,
        ModeType.oblique => 1.0,
      };

  String get label => switch (this) {
        ModeType.axial => 'Axial',
        ModeType.tangential => 'Tangential',
        ModeType.oblique => 'Oblique',
      };
}

/// A single room mode: its integer indices (p, q, r) along length, width and
/// height, its resonant [frequency] in Hz, and its [type].
class RoomMode {
  const RoomMode({
    required this.p,
    required this.q,
    required this.r,
    required this.frequency,
  });

  final int p;
  final int q;
  final int r;
  final double frequency;

  /// Number of non-zero indices, which determines the mode type.
  int get order =>
      (p != 0 ? 1 : 0) + (q != 0 ? 1 : 0) + (r != 0 ? 1 : 0);

  ModeType get type => switch (order) {
        1 => ModeType.axial,
        2 => ModeType.tangential,
        _ => ModeType.oblique,
      };

  double get strength => type.strength;

  @override
  String toString() =>
      '($p,$q,$r) ${frequency.toStringAsFixed(1)} Hz ${type.label}';
}
