import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/geometry/render_mesh.dart';
import '../../core/numeric/modal_analysis.dart';

/// A touch-rotatable 3D view of a computed (arbitrary-shape) mode. Renders
/// the room's boundary surface -- the native FEM solver's own solve-mesh
/// boundary, or the Dart FDM fallback's voxel-grid boundary -- colored by
/// the mode's pressure field with smooth per-vertex (Gouraud) shading via
/// [Canvas.drawVertices]. Drag to orbit.
class ComputedMode3DView extends StatefulWidget {
  const ComputedMode3DView({
    super.key,
    required this.mesh,
    required this.mode,
  });

  final RenderMesh mesh;
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
        painter: _MeshFieldPainter(
          mesh: widget.mesh,
          field: widget.mode.field,
          yaw: _yaw,
          pitch: _pitch,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MeshFieldPainter extends CustomPainter {
  _MeshFieldPainter({
    required this.mesh,
    required this.field,
    required this.yaw,
    required this.pitch,
  });

  final RenderMesh mesh;
  final Float64List field;
  final double yaw;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeCount = mesh.nodeCount;
    // ui.Vertices.raw's indices are Uint16, so node indices must fit in 16
    // bits. In practice solve meshes top out in the hundreds of boundary
    // nodes even at max resolution/mode-count (verified against the UI's
    // slider ranges), so this only guards a pathological case.
    if (nodeCount == 0 || nodeCount > 65535) return;

    var minX = double.infinity, minY = double.infinity, minZ = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity, maxZ = -double.infinity;
    for (var i = 0; i < nodeCount; i++) {
      final x = mesh.x(i), y = mesh.y(i), z = mesh.z(i);
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      if (z < minZ) minZ = z;
      if (z > maxZ) maxZ = z;
    }
    final cx0 = (minX + maxX) / 2, cy0 = (minY + maxY) / 2, cz0 = (minZ + maxZ) / 2;
    final diag = math.sqrt(math.pow(maxX - minX, 2) + math.pow(maxY - minY, 2) +
        math.pow(maxZ - minZ, 2));
    final scale = diag > 0 ? 0.62 * math.min(size.width, size.height) / diag : 1.0;
    final center = Offset(size.width / 2, size.height / 2);

    final cosY = math.cos(yaw), sinY = math.sin(yaw);
    final cosP = math.cos(pitch), sinP = math.sin(pitch);

    // Project every node once; triangles just reference these shared points,
    // so (unlike the old per-voxel-face painter) no vertex is ever
    // duplicated for geometry -- only depth-sorting needs a second pass.
    final points = Float32List(nodeCount * 2);
    final depths = Float64List(nodeCount);
    for (var i = 0; i < nodeCount; i++) {
      final px = mesh.x(i) - cx0, py = mesh.y(i) - cy0, pz = mesh.z(i) - cz0;
      final x1 = px * cosY - py * sinY;
      final y1 = px * sinY + py * cosY;
      final y2 = y1 * cosP - pz * sinP;
      final z2 = y1 * sinP + pz * cosP;
      final o = center + Offset(x1 * scale, -z2 * scale);
      points[i * 2] = o.dx;
      points[i * 2 + 1] = o.dy;
      depths[i] = y2;
    }

    var maxAbs = 1e-12;
    for (final v in field) {
      final a = v.abs();
      if (a > maxAbs) maxAbs = a;
    }
    final colors = Int32List(nodeCount);
    for (var i = 0; i < nodeCount; i++) {
      colors[i] = _pressureColor(field[i] / maxAbs).toARGB32();
    }

    // Painter's algorithm: draw triangles back-to-front. Only the triangle
    // *order* is sorted (via their average vertex depth) -- points/colors
    // stay shared, so this is just a reordering of the indices array.
    final triCount = mesh.triangleCount;
    final order = List<int>.generate(triCount, (i) => i);
    double triDepth(int t) =>
        (depths[mesh.triangles[t * 3]] +
            depths[mesh.triangles[t * 3 + 1]] +
            depths[mesh.triangles[t * 3 + 2]]) /
        3;
    order.sort((a, b) => triDepth(a).compareTo(triDepth(b)));

    final indices = Uint16List(triCount * 3);
    for (var i = 0; i < triCount; i++) {
      final t = order[i];
      indices[i * 3] = mesh.triangles[t * 3];
      indices[i * 3 + 1] = mesh.triangles[t * 3 + 1];
      indices[i * 3 + 2] = mesh.triangles[t * 3 + 2];
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      points,
      colors: colors,
      indices: indices,
    );
    canvas.drawVertices(vertices, ui.BlendMode.srcOver, Paint());
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
  bool shouldRepaint(_MeshFieldPainter old) =>
      old.mesh != mesh || old.field != field || old.yaw != yaw || old.pitch != pitch;
}
