import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustics/mode.dart';
import '../../core/acoustics/pressure_field.dart';
import '../../core/acoustics/room.dart';
import '../../state/room_providers.dart';

/// A touch-rotatable 3D view of the selected mode. The room is drawn as a box
/// whose six walls are colored by the mode's standing-pressure pattern
/// (red = +, blue = −, dark = nodal lines), so you can see where the pressure
/// peaks and nulls sit in the actual room. Drag to orbit.
///
/// Deliberately a hand-rolled orthographic painter (no 3D engine) to keep the
/// app small and the frame cheap. It visualizes the analytical cuboid mode via
/// [pressureAt]; the Phase 2 solver's fields for arbitrary shapes can plug into
/// the same renderer later.
class Mode3DView extends ConsumerStatefulWidget {
  const Mode3DView({super.key});

  @override
  ConsumerState<Mode3DView> createState() => _Mode3DViewState();
}

class _Mode3DViewState extends ConsumerState<Mode3DView> {
  // Start at a three-quarter view so the box reads as 3D immediately.
  double _yaw = -0.7;
  double _pitch = -0.45;

  @override
  Widget build(BuildContext context) {
    final modes = ref.watch(modesProvider);
    final index = ref.watch(selectedModeIndexProvider);
    final room = ref.watch(roomProvider);

    if (index == null || index >= modes.length) {
      return const Card(
        margin: EdgeInsets.all(12),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('Select a mode to see it in 3D')),
        ),
      );
    }

    final mode = modes[index];

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '3D — mode (${mode.p},${mode.q},${mode.r})  '
              '${mode.frequency.toStringAsFixed(1)} Hz  ${mode.type.label}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Drag to rotate • walls colored by pressure',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1.3,
              child: GestureDetector(
                onPanUpdate: (d) {
                  setState(() {
                    _yaw += d.delta.dx * 0.01;
                    _pitch =
                        (_pitch + d.delta.dy * 0.01).clamp(-1.5, 1.5);
                  });
                },
                child: CustomPaint(
                  painter: _Room3DPainter(
                    mode: mode,
                    room: room,
                    yaw: _yaw,
                    pitch: _pitch,
                    edgeColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Room3DPainter extends CustomPainter {
  _Room3DPainter({
    required this.mode,
    required this.room,
    required this.yaw,
    required this.pitch,
    required this.edgeColor,
  });

  final RoomMode mode;
  final Room room;
  final double yaw;
  final double pitch;
  final Color edgeColor;

  static const int _cells = 12; // grid resolution per wall

  @override
  void paint(Canvas canvas, Size size) {
    final l = room.length, w = room.width, h = room.height;
    final diag = math.sqrt(l * l + w * w + h * h);
    final scale = 0.62 * math.min(size.width, size.height) / diag;
    final center = Offset(size.width / 2, size.height / 2);

    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);

    // Projects a room-space point to (screen offset, depth toward viewer).
    (Offset, double) project(double x, double y, double z) {
      final cx = x - l / 2, cy = y - w / 2, cz = z - h / 2;
      // Yaw about the vertical (z) axis, then pitch about the screen x axis.
      final x1 = cx * cosY - cy * sinY;
      final y1 = cx * sinY + cy * cosY;
      final z1 = cz;
      final y2 = y1 * cosP - z1 * sinP;
      final z2 = y1 * sinP + z1 * cosP;
      return (
        center + Offset(x1 * scale, -z2 * scale),
        y2, // larger = closer to the viewer
      );
    }

    final quads = <_Quad>[];

    // Each wall: fixed coordinate + two varying axes over [0,1].
    void addWall(
      ({double x, double y, double z}) Function(double a, double b) at,
    ) {
      for (var ia = 0; ia < _cells; ia++) {
        for (var ib = 0; ib < _cells; ib++) {
          final a0 = ia / _cells, a1 = (ia + 1) / _cells;
          final b0 = ib / _cells, b1 = (ib + 1) / _cells;
          final c0 = at(a0, b0);
          final c1 = at(a1, b0);
          final c2 = at(a1, b1);
          final c3 = at(a0, b1);
          final mid = at((a0 + a1) / 2, (b0 + b1) / 2);
          final p = pressureAt(mode, room, x: mid.x, y: mid.y, z: mid.z);
          final (s0, d0) = project(c0.x, c0.y, c0.z);
          final (s1, d1) = project(c1.x, c1.y, c1.z);
          final (s2, d2) = project(c2.x, c2.y, c2.z);
          final (s3, d3) = project(c3.x, c3.y, c3.z);
          quads.add(_Quad(
            [s0, s1, s2, s3],
            (d0 + d1 + d2 + d3) / 4,
            _pressureColor(p),
          ));
        }
      }
    }

    addWall((a, b) => (x: 0, y: a * w, z: b * h)); // x = 0
    addWall((a, b) => (x: l, y: a * w, z: b * h)); // x = L
    addWall((a, b) => (x: a * l, y: 0, z: b * h)); // y = 0
    addWall((a, b) => (x: a * l, y: w, z: b * h)); // y = W
    addWall((a, b) => (x: a * l, y: b * w, z: 0)); // z = 0
    addWall((a, b) => (x: a * l, y: b * w, z: h)); // z = H

    // Painter's algorithm: far walls first.
    quads.sort((p, q) => p.depth.compareTo(q.depth));
    final fill = Paint()..style = PaintingStyle.fill;
    for (final quad in quads) {
      final path = Path()..addPolygon(quad.points, true);
      canvas.drawPath(path, fill..color = quad.color);
    }

    _drawEdges(canvas, project);
  }

  void _drawEdges(
    Canvas canvas,
    (Offset, double) Function(double, double, double) project,
  ) {
    final l = room.length, w = room.width, h = room.height;
    final edge = Paint()
      ..color = edgeColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final corners = [
      for (final z in [0.0, h])
        for (final y in [0.0, w])
          for (final x in [0.0, l]) project(x, y, z).$1,
    ];
    // Indices into the 8 corners (x fastest, then y, then z).
    const edges = [
      [0, 1], [2, 3], [4, 5], [6, 7], // x-direction
      [0, 2], [1, 3], [4, 6], [5, 7], // y-direction
      [0, 4], [1, 5], [2, 6], [3, 7], // z-direction
    ];
    for (final e in edges) {
      canvas.drawLine(corners[e[0]], corners[e[1]], edge);
    }
  }

  /// Diverging blue–black–red color for a signed pressure in [-1, 1].
  Color _pressureColor(double v) {
    final m = v.abs().clamp(0.0, 1.0);
    if (v >= 0) {
      return Color.fromARGB(
          255, (m * 255).round(), (m * 60).round(), (m * 40).round());
    }
    return Color.fromARGB(
        255, (m * 40).round(), (m * 80).round(), (m * 255).round());
  }

  @override
  bool shouldRepaint(_Room3DPainter old) =>
      old.mode != mode ||
      old.room != room ||
      old.yaw != yaw ||
      old.pitch != pitch;
}

class _Quad {
  _Quad(this.points, this.depth, this.color);
  final List<Offset> points;
  final double depth;
  final Color color;
}
