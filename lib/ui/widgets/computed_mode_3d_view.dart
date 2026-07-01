import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/geometry/voxel_grid.dart';
import '../../core/numeric/modal_analysis.dart';

/// A touch-rotatable 3D view of a computed (arbitrary-shape) mode. Renders the
/// room's surface — every voxel face that borders a wall — colored by the
/// mode's pressure field (red +, blue −, dark ≈ node). Drag to orbit.
class ComputedMode3DView extends StatefulWidget {
  const ComputedMode3DView({
    super.key,
    required this.grid,
    required this.mode,
  });

  final VoxelGrid grid;
  final ComputedMode mode;

  @override
  State<ComputedMode3DView> createState() => _ComputedMode3DViewState();
}

class _ComputedMode3DViewState extends State<ComputedMode3DView> {
  double _yaw = -0.7;
  double _pitch = -0.45;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) {
        setState(() {
          _yaw += d.delta.dx * 0.01;
          _pitch = (_pitch + d.delta.dy * 0.01).clamp(-1.5, 1.5);
        });
      },
      child: CustomPaint(
        painter: _ComputedFieldPainter(
          grid: widget.grid,
          field: widget.mode.field,
          yaw: _yaw,
          pitch: _pitch,
          edgeColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ComputedFieldPainter extends CustomPainter {
  _ComputedFieldPainter({
    required this.grid,
    required this.field,
    required this.yaw,
    required this.pitch,
    required this.edgeColor,
  });

  final VoxelGrid grid;
  final Float64List field;
  final double yaw;
  final double pitch;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final h = grid.h;
    final boxX = grid.nx * h, boxY = grid.ny * h, boxZ = grid.nz * h;
    final cx0 = grid.originX + boxX / 2;
    final cy0 = grid.originY + boxY / 2;
    final cz0 = grid.originZ + boxZ / 2;
    final diag = math.sqrt(boxX * boxX + boxY * boxY + boxZ * boxZ);
    final scale = 0.62 * math.min(size.width, size.height) / diag;
    final center = Offset(size.width / 2, size.height / 2);

    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);

    (Offset, double) project(double x, double y, double z) {
      final px = x - cx0, py = y - cy0, pz = z - cz0;
      final x1 = px * cosY - py * sinY;
      final y1 = px * sinY + py * cosY;
      final y2 = y1 * cosP - pz * sinP;
      final z2 = y1 * sinP + pz * cosP;
      return (center + Offset(x1 * scale, -z2 * scale), y2);
    }

    // Normalize field for color mapping.
    var maxAbs = 1e-12;
    for (final v in field) {
      final a = v.abs();
      if (a > maxAbs) maxAbs = a;
    }

    final quads = <_Quad>[];
    // Face corner offsets (in cell units) for each of the 6 neighbour dirs.
    for (var c = 0; c < grid.cellCount; c++) {
      final i = grid.ci[c], j = grid.cj[c], k = grid.ck[c];
      final x0 = grid.originX + i * h, x1 = x0 + h;
      final y0 = grid.originY + j * h, y1 = y0 + h;
      final z0 = grid.originZ + k * h, z1 = z0 + h;
      final base = c * 6;
      final color = _pressureColor(field[c] / maxAbs);

      void face(List<(double, double, double)> corners) {
        final projected = <Offset>[];
        var depth = 0.0;
        for (final (x, y, z) in corners) {
          final (o, d) = project(x, y, z);
          projected.add(o);
          depth += d;
        }
        quads.add(_Quad(projected, depth / corners.length, color));
      }

      if (grid.neighbors[base + 0] < 0) {
        face([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)]);
      }
      if (grid.neighbors[base + 1] < 0) {
        face([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)]);
      }
      if (grid.neighbors[base + 2] < 0) {
        face([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)]);
      }
      if (grid.neighbors[base + 3] < 0) {
        face([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]);
      }
      if (grid.neighbors[base + 4] < 0) {
        face([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)]);
      }
      if (grid.neighbors[base + 5] < 0) {
        face([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]);
      }
    }

    quads.sort((p, q) => p.depth.compareTo(q.depth));
    final fill = Paint()..style = PaintingStyle.fill;
    for (final quad in quads) {
      canvas.drawPath(
        Path()..addPolygon(quad.points, true),
        fill..color = quad.color,
      );
    }
  }

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
  bool shouldRepaint(_ComputedFieldPainter old) =>
      old.field != field || old.yaw != yaw || old.pitch != pitch;
}

class _Quad {
  _Quad(this.points, this.depth, this.color);
  final List<Offset> points;
  final double depth;
  final Color color;
}
