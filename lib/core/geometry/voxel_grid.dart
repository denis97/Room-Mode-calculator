import 'dart:math' as math;
import 'dart:typed_data';

import 'room_shape.dart';

/// A regular voxelization of a [RoomShape] for finite-difference modal
/// analysis. Cubic cells of side [h] tile the shape's bounding box; a cell
/// belongs to the domain when its centre is inside the shape.
///
/// Inside cells are given a compact index 0..[cellCount); for each one the
/// compact indices of its six axis neighbours are precomputed in [neighbors]
/// (-1 where the neighbour is outside the room — i.e. a rigid wall). The
/// solver works purely off this connectivity, so it is shape-agnostic.
class VoxelGrid {
  VoxelGrid._({
    required this.nx,
    required this.ny,
    required this.nz,
    required this.h,
    required this.originX,
    required this.originY,
    required this.originZ,
    required this.cellCount,
    required this.ci,
    required this.cj,
    required this.ck,
    required this.neighbors,
  });

  /// Grid resolution along each axis (bounding-box cells).
  final int nx;
  final int ny;
  final int nz;

  /// Cell size in metres (cubic cells).
  final double h;

  final double originX;
  final double originY;
  final double originZ;

  /// Number of inside cells (the linear system size).
  final int cellCount;

  /// Cell (i, j, k) indices for each compact cell.
  final Int32List ci;
  final Int32List cj;
  final Int32List ck;

  /// Six neighbour compact indices per cell (−x, +x, −y, +y, −z, +z); −1 when
  /// the neighbour lies outside the room.
  final Int32List neighbors;

  /// World-space centre of a compact cell.
  (double, double, double) cellCenter(int c) => (
        originX + (ci[c] + 0.5) * h,
        originY + (cj[c] + 0.5) * h,
        originZ + (ck[c] + 0.5) * h,
      );

  /// Builds a grid from raw arrays already matching this class's invariants
  /// (compact indices 0..cellCount, six-neighbour connectivity) -- used by
  /// the native solver's FFI bridge, which voxelizes the same way this class
  /// does natively and hands back the result over the C ABI.
  factory VoxelGrid.fromNativeData({
    required int nx,
    required int ny,
    required int nz,
    required double h,
    required double originX,
    required double originY,
    required double originZ,
    required int cellCount,
    required Int32List ci,
    required Int32List cj,
    required Int32List ck,
    required Int32List neighbors,
  }) {
    return VoxelGrid._(
      nx: nx,
      ny: ny,
      nz: nz,
      h: h,
      originX: originX,
      originY: originY,
      originZ: originZ,
      cellCount: cellCount,
      ci: ci,
      cj: cj,
      ck: ck,
      neighbors: neighbors,
    );
  }

  /// Builds a grid covering [shape] with roughly [targetPerAxis] cubic cells
  /// along the longest axis.
  factory VoxelGrid.fromShape(RoomShape shape, {int targetPerAxis = 16}) {
    final maxExtent =
        [shape.extentX, shape.extentY, shape.extentZ].reduce(math.max);
    final h = maxExtent / targetPerAxis;
    final nx = math.max(1, (shape.extentX / h).ceil());
    final ny = math.max(1, (shape.extentY / h).ceil());
    final nz = math.max(1, (shape.extentZ / h).ceil());

    // First pass: classify cells and assign compact indices.
    final total = nx * ny * nz;
    final compact = Int32List(total)..fillRange(0, total, -1);
    final ciList = <int>[];
    final cjList = <int>[];
    final ckList = <int>[];
    int lin(int i, int j, int k) => (k * ny + j) * nx + i;

    for (var k = 0; k < nz; k++) {
      final cz = shape.originZ + (k + 0.5) * h;
      for (var j = 0; j < ny; j++) {
        final cy = shape.originY + (j + 0.5) * h;
        for (var i = 0; i < nx; i++) {
          final cx = shape.originX + (i + 0.5) * h;
          if (shape.contains(cx, cy, cz)) {
            compact[lin(i, j, k)] = ciList.length;
            ciList.add(i);
            cjList.add(j);
            ckList.add(k);
          }
        }
      }
    }

    final cellCount = ciList.length;
    final ci = Int32List.fromList(ciList);
    final cj = Int32List.fromList(cjList);
    final ck = Int32List.fromList(ckList);

    // Second pass: precompute six-neighbour connectivity.
    final neighbors = Int32List(cellCount * 6);
    int neighborAt(int i, int j, int k) {
      if (i < 0 || i >= nx || j < 0 || j >= ny || k < 0 || k >= nz) return -1;
      return compact[lin(i, j, k)];
    }

    for (var c = 0; c < cellCount; c++) {
      final i = ci[c], j = cj[c], k = ck[c];
      final base = c * 6;
      neighbors[base + 0] = neighborAt(i - 1, j, k);
      neighbors[base + 1] = neighborAt(i + 1, j, k);
      neighbors[base + 2] = neighborAt(i, j - 1, k);
      neighbors[base + 3] = neighborAt(i, j + 1, k);
      neighbors[base + 4] = neighborAt(i, j, k - 1);
      neighbors[base + 5] = neighborAt(i, j, k + 1);
    }

    return VoxelGrid._(
      nx: nx,
      ny: ny,
      nz: nz,
      h: h,
      originX: shape.originX,
      originY: shape.originY,
      originZ: shape.originZ,
      cellCount: cellCount,
      ci: ci,
      cj: cj,
      ck: ck,
      neighbors: neighbors,
    );
  }
}
