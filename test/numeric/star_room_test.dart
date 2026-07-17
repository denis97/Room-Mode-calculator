import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/numeric/native/room_mode_bindings.dart';
import 'dart:math' as math;

void main() {
  group('Custom room solver - complex geometries', () {
    test('10-point star floor plan at various resolutions', () {
      // Generate a 10-point star: alternating inner & outer radii
      final vertices = <(double, double)>[];
      const outerRadius = 5.0;
      const innerRadius = 2.0;
      const points = 10;

      for (var i = 0; i < points; i++) {
        final angle = 2 * math.pi * i / points;
        final radius = (i % 2 == 0) ? outerRadius : innerRadius;
        vertices.add((
          5.0 + radius * math.cos(angle),
          5.0 + radius * math.sin(angle),
        ));
      }

      final polygonX = vertices.map((v) => v.$1).toList();
      final polygonY = vertices.map((v) => v.$2).toList();

      // ignore: avoid_print
      print('Testing 10-point star: ${vertices.length} vertices');
      // ignore: avoid_print
      print('Vertices: $vertices');

      // Test at different resolutions
      for (int res = 10; res <= 30; res += 5) {
        try {
          // ignore: avoid_print
          print('\nResolution: $res');

          final nativeX =
              polygonX.cast<double>().toList(); // FFI conversion
          final nativeY =
              polygonY.cast<double>().toList();

          // Allocate native memory for polygon vertices
          final ptrX = calloc<ffi.Double>(nativeX.length);
          final ptrY = calloc<ffi.Double>(nativeY.length);

          // Copy data to native memory
          for (var i = 0; i < nativeX.length; i++) {
            ptrX[i] = nativeX[i];
            ptrY[i] = nativeY[i];
          }

          // Call native solver
          final lib = RoomModeNativeLibrary.instance;
          final result = lib.solveRoomModes(
            ptrX,
            ptrY,
            nativeX.length,
            3.0, // height
            20.0, // temperature C
            res, // targetPerAxis
            8, // modeCount
          );

          // Free native memory
          calloc.free(ptrX);
          calloc.free(ptrY);

          if (result.ref.success == 0) {
            final errPtr = result.ref.errorMessage;
            final errMsg = errPtr == ffi.nullptr
                ? 'Unknown error'
                : errPtr.cast<Utf8>().toDartString();
            // ignore: avoid_print
            print('  -> ERROR: $errMsg');
            lib.freeSolveResult(result);
            continue;
          }

          // ignore: avoid_print
          print(
              '  -> Success: ${result.ref.modeCount} modes, ${result.ref.nodeCount} nodes, ${result.ref.triCount ~/ 3} triangles');

          // Print mode frequencies
          final freqs =
              result.ref.frequencies.asTypedList(result.ref.modeCount);
          for (var i = 0; i < result.ref.modeCount; i++) {
            // ignore: avoid_print
            print('     Mode ${i + 1}: ${freqs[i].toStringAsFixed(1)} Hz');
          }

          lib.freeSolveResult(result);
        } catch (e) {
          // ignore: avoid_print
          print('  -> EXCEPTION: $e');
        }
      }
    });
  });
}
