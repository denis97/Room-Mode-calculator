import 'dart:math' as math;

/// A 3D room shape for numerical modal analysis. All coordinates are in metres.
///
/// A shape exposes its axis-aligned bounding box (origin + extents) and a
/// point-containment test. The voxelizer samples cell centres against
/// [contains] to build the finite-difference domain, so any shape that can
/// answer "is this point inside the room?" can be analysed — not just cuboids.
abstract class RoomShape {
  double get originX;
  double get originY;
  double get originZ;

  double get extentX;
  double get extentY;
  double get extentZ;

  bool contains(double x, double y, double z);
}

/// A rectangular (cuboid) room. This is the analytical case and is used to
/// validate the numerical solver against the closed-form mode formula.
class BoxShape implements RoomShape {
  const BoxShape({
    required this.length,
    required this.width,
    required this.height,
  });

  final double length;
  final double width;
  final double height;

  @override
  double get originX => 0;
  @override
  double get originY => 0;
  @override
  double get originZ => 0;

  @override
  double get extentX => length;
  @override
  double get extentY => width;
  @override
  double get extentZ => height;

  @override
  bool contains(double x, double y, double z) =>
      x >= 0 && x <= length && y >= 0 && y <= width && z >= 0 && z <= height;
}

/// A room whose floor is an arbitrary polygon (list of (x, y) vertices in
/// metres, any winding) extruded vertically to [height]. This is the first
/// non-rectangular shape the FEM/FDM path supports.
class ExtrudedPolygonShape implements RoomShape {
  ExtrudedPolygonShape({required this.floor, required this.height})
      : assert(floor.length >= 3, 'A floor polygon needs at least 3 vertices') {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final (px, py) in floor) {
      minX = math.min(minX, px);
      maxX = math.max(maxX, px);
      minY = math.min(minY, py);
      maxY = math.max(maxY, py);
    }
    _minX = minX;
    _minY = minY;
    _extentX = maxX - minX;
    _extentY = maxY - minY;
  }

  final List<(double, double)> floor;
  final double height;

  late final double _minX;
  late final double _minY;
  late final double _extentX;
  late final double _extentY;

  @override
  double get originX => _minX;
  @override
  double get originY => _minY;
  @override
  double get originZ => 0;

  @override
  double get extentX => _extentX;
  @override
  double get extentY => _extentY;
  @override
  double get extentZ => height;

  /// Floor area in m², via the shoelace formula (winding-independent).
  double get floorArea {
    var sum = 0.0;
    final n = floor.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      sum += (floor[j].$1 + floor[i].$1) * (floor[j].$2 - floor[i].$2);
    }
    return sum.abs() / 2;
  }

  @override
  bool contains(double x, double y, double z) {
    if (z < 0 || z > height) return false;
    return _pointInPolygon(x, y);
  }

  /// Standard ray-casting point-in-polygon test.
  bool _pointInPolygon(double x, double y) {
    var inside = false;
    final n = floor.length;
    for (var i = 0, j = n - 1; i < n; j = i++) {
      final (xi, yi) = floor[i];
      final (xj, yj) = floor[j];
      final crosses = (yi > y) != (yj > y) &&
          x < (xj - xi) * (y - yi) / (yj - yi) + xi;
      if (crosses) inside = !inside;
    }
    return inside;
  }
}
