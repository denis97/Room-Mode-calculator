import 'dart:ffi' as ffi;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart' as pkg_ffi;

import '../../acoustics/speed_of_sound.dart';
import '../../geometry/room_shape.dart';
import '../../geometry/voxel_grid.dart';
import '../modal_analysis.dart';
import 'room_mode_bindings.dart';

/// Thrown when the native solver reports failure (e.g. a self-intersecting
/// or degenerate floor plan).
class NativeSolverException implements Exception {
  NativeSolverException(this.message);
  final String message;
  @override
  String toString() => 'NativeSolverException: $message';
}

/// Computes the room modes of [shape] using the native FEM solver (see
/// native/README.md) instead of the pure-Dart finite-volume path in
/// modal_analysis.dart. Returns the exact same [ModalAnalysisResult] shape,
/// so callers and UI widgets don't need to know which solver produced it.
///
/// Only [ExtrudedPolygonShape] is supported (the native path exists for
/// arbitrary/non-rectangular rooms; a [BoxShape] already has an exact
/// analytical formula and doesn't need a numerical solve at all).
ModalAnalysisResult analyzeRoomShapeNative(
  ExtrudedPolygonShape shape, {
  required double temperatureC,
  required int targetPerAxis,
  required int modeCount,
}) {
  final n = shape.floor.length;
  final polygonX = pkg_ffi.calloc<ffi.Double>(n);
  final polygonY = pkg_ffi.calloc<ffi.Double>(n);
  try {
    for (var i = 0; i < n; i++) {
      polygonX[i] = shape.floor[i].$1;
      polygonY[i] = shape.floor[i].$2;
    }

    final lib = RoomModeNativeLibrary.instance;
    final resultPtr = lib.solveRoomModes(
      polygonX,
      polygonY,
      n,
      shape.height,
      temperatureC,
      targetPerAxis,
      modeCount,
    );

    try {
      final result = resultPtr.ref;
      if (result.success == 0) {
        final message = result.errorMessage == ffi.nullptr
            ? 'Unknown native solver error'
            : result.errorMessage.cast<pkg_ffi.Utf8>().toDartString();
        throw NativeSolverException(message);
      }

      // Copy every array out of native memory into Dart-owned typed lists
      // *before* freeing the native result -- .asTypedList() is a view into
      // native memory, not a copy, and would dangle once freed.
      final cellCount = result.cellCount;
      final ci = Int32List.fromList(result.ci.asTypedList(cellCount));
      final cj = Int32List.fromList(result.cj.asTypedList(cellCount));
      final ck = Int32List.fromList(result.ck.asTypedList(cellCount));
      final neighbors =
          Int32List.fromList(result.neighbors.asTypedList(cellCount * 6));

      final grid = VoxelGrid.fromNativeData(
        nx: result.nx,
        ny: result.ny,
        nz: result.nz,
        h: result.h,
        originX: result.originX,
        originY: result.originY,
        originZ: result.originZ,
        cellCount: cellCount,
        ci: ci,
        cj: cj,
        ck: ck,
        neighbors: neighbors,
      );

      final c = speedOfSound(temperatureC: temperatureC);
      final frequencies =
          result.frequencies.asTypedList(result.modeCount);
      final fields = result.fields.asTypedList(result.modeCount * cellCount);
      final modes = <ComputedMode>[];
      for (var m = 0; m < result.modeCount; m++) {
        final frequency = frequencies[m];
        final field = Float64List.fromList(
          fields.sublist(m * cellCount, (m + 1) * cellCount),
        );
        // Inverse of f = c*sqrt(mu)/(2*pi), matching modal_analysis.dart.
        final eigenvalue = math.pow(2 * math.pi * frequency / c, 2).toDouble();
        modes.add(ComputedMode(frequency: frequency, eigenvalue: eigenvalue, field: field));
      }

      return ModalAnalysisResult(grid: grid, modes: modes);
    } finally {
      lib.freeSolveResult(resultPtr);
    }
  } finally {
    pkg_ffi.calloc.free(polygonX);
    pkg_ffi.calloc.free(polygonY);
  }
}
