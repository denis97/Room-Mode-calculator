import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/geometry/room_shape.dart';
import 'package:room_mode_calculator/core/geometry/voxel_grid.dart';

void main() {
  test('a box that fills its bounding box voxelizes to a full grid', () {
    const box = BoxShape(length: 4, width: 3, height: 2);
    final grid = VoxelGrid.fromShape(box, targetPerAxis: 12);

    // h = 4 / 12, so the extents divide evenly: 12 x 9 x 6 cells, all inside.
    expect(grid.nx, 12);
    expect(grid.ny, 9);
    expect(grid.nz, 6);
    expect(grid.cellCount, 12 * 9 * 6);
  });

  test('corner cells have 3 wall faces, interior cells have none', () {
    const box = BoxShape(length: 4, width: 3, height: 2);
    final grid = VoxelGrid.fromShape(box, targetPerAxis: 12);

    // Iteration order means compact cell 0 is grid corner (0, 0, 0).
    expect([grid.ci[0], grid.cj[0], grid.ck[0]], [0, 0, 0]);
    var cornerNeighbors = 0;
    for (var d = 0; d < 6; d++) {
      if (grid.neighbors[0 * 6 + d] >= 0) cornerNeighbors++;
    }
    expect(cornerNeighbors, 3); // +x, +y, +z only

    // Find an interior cell (not on any face) and check all six neighbours.
    final interior = List.generate(grid.cellCount, (c) => c).firstWhere((c) =>
        grid.ci[c] > 0 &&
        grid.ci[c] < grid.nx - 1 &&
        grid.cj[c] > 0 &&
        grid.cj[c] < grid.ny - 1 &&
        grid.ck[c] > 0 &&
        grid.ck[c] < grid.nz - 1);
    var interiorNeighbors = 0;
    for (var d = 0; d < 6; d++) {
      if (grid.neighbors[interior * 6 + d] >= 0) interiorNeighbors++;
    }
    expect(interiorNeighbors, 6);
  });

  test('a square extruded polygon matches the equivalent box', () {
    final poly = ExtrudedPolygonShape(
      floor: const [(0, 0), (4, 0), (4, 3), (0, 3)],
      height: 2,
    );
    final grid = VoxelGrid.fromShape(poly, targetPerAxis: 12);
    expect(grid.cellCount, 12 * 9 * 6);
  });

  test('an L-shaped floor excludes the notch', () {
    // L-shape: full 4x4 with the top-right 2x2 quadrant removed.
    final lShape = ExtrudedPolygonShape(
      floor: const [(0, 0), (4, 0), (4, 2), (2, 2), (2, 4), (0, 4)],
      height: 3,
    );
    expect(lShape.contains(1, 1, 1.5), isTrue); // lower-left, inside
    expect(lShape.contains(3, 3, 1.5), isFalse); // removed notch
    expect(lShape.contains(1, 3, 1.5), isTrue); // left arm, inside
    expect(lShape.contains(1, 1, 5), isFalse); // above the ceiling

    final grid = VoxelGrid.fromShape(lShape, targetPerAxis: 12);
    // The notch removes roughly a quarter of the footprint.
    final fullFootprintCells = grid.nx * grid.ny * grid.nz;
    expect(grid.cellCount, lessThan(fullFootprintCells));
    expect(grid.cellCount, greaterThan(0.6 * fullFootprintCells));
  });
}
