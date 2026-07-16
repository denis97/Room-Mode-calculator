import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/numeric/modal_analysis.dart';
import 'package:room_mode_calculator/core/geometry/room_shape.dart';
import 'package:room_mode_calculator/core/numeric/native/native_modal_solver.dart';
import 'dart:math' as math;

void main() {
  group('Custom room solver - complex geometries', () {
    test('10-point star floor plan at various resolutions', () async {
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

      final room = CustomRoomShape(
        floorPlanX: vertices.map((v) => v.$1).toList(),
        floorPlanY: vertices.map((v) => v.$2).toList(),
        heightM: 3.0,
      );

      print('Testing 10-point star: ${vertices.length} vertices');
      print('Vertices: $vertices');

      // Test at different resolutions
      for (int res = 10; res <= 30; res += 5) {
        try {
          print('\nResolution: $res');
          final result = await nativeModalSolver(
            room: room,
            modeCount: 8,
            resolutionPerAxis: res,
          );

          if (result == null) {
            print('  -> Solver returned null');
            continue;
          }

          print('  -> Success: ${result.modes.length} modes computed');
          print('  -> Mesh nodes: ${result.mesh.positions.length ~/ 3}');
          print('  -> Mesh triangles: ${result.mesh.triangles.length ~/ 3}');

          // Print mode frequencies
          for (var i = 0; i < result.modes.length; i++) {
            print('     Mode ${i + 1}: ${result.modes[i].frequency.toStringAsFixed(1)} Hz');
          }
        } catch (e) {
          print('  -> ERROR: $e');
        }
      }
    });
  });
}
