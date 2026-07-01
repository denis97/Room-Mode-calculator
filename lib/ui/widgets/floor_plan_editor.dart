import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/custom_room_providers.dart';

/// An interactive top-down editor for the room's floor polygon.
///
/// - **Drag** a vertex to move it (snaps to a 0.25 m grid and locks to 90°
///   against neighbouring vertices).
/// - **Tap** an empty spot to insert a vertex on the nearest edge.
/// - **Long-press** near a vertex to delete it (minimum three remain).
/// - **Pinch** (two fingers) to zoom and pan.
///
/// Coordinates are metres on a fixed [worldSize]×[worldSize] field with a 1 m
/// grid marked by tick crosses; edits write straight to [floorPlanProvider].
class FloorPlanEditor extends ConsumerStatefulWidget {
  const FloorPlanEditor({super.key});

  static const double worldSize = 8.0; // metres shown per axis

  @override
  ConsumerState<FloorPlanEditor> createState() => _FloorPlanEditorState();
}

class _FloorPlanEditorState extends ConsumerState<FloorPlanEditor> {
  int? _dragIndex;
  double _canvasSize = 1;

  double get _scale => _canvasSize / FloorPlanEditor.worldSize;

  Offset _worldToLocal((double, double) v) =>
      Offset(v.$1 * _scale, v.$2 * _scale);

  (double, double) _localToWorld(Offset p) => (
        (p.dx / _scale).clamp(0.0, FloorPlanEditor.worldSize),
        (p.dy / _scale).clamp(0.0, FloorPlanEditor.worldSize),
      );

  static const double _snapGrid = 0.25; // metres

  /// Snaps a dragged vertex to a 0.25 m grid, and aligns it to a neighbour's
  /// row or column when close — so edges lock to horizontal/vertical (90°).
  (double, double) _snap(
      (double, double) p, List<(double, double)> verts, int index) {
    var sx = (p.$1 / _snapGrid).round() * _snapGrid;
    var sy = (p.$2 / _snapGrid).round() * _snapGrid;
    final n = verts.length;
    final prev = verts[(index - 1 + n) % n];
    final next = verts[(index + 1) % n];
    const tol = 0.4; // metres — align to neighbour axis within this distance
    if ((sx - prev.$1).abs() < tol) {
      sx = prev.$1;
    } else if ((sx - next.$1).abs() < tol) {
      sx = next.$1;
    }
    if ((sy - prev.$2).abs() < tol) {
      sy = prev.$2;
    } else if ((sy - next.$2).abs() < tol) {
      sy = next.$2;
    }
    final w = FloorPlanEditor.worldSize;
    return (sx.clamp(0.0, w), sy.clamp(0.0, w));
  }

  int? _nearestVertex(Offset local, List<(double, double)> verts) {
    var best = -1;
    var bestDist = 24.0; // px hit radius
    for (var i = 0; i < verts.length; i++) {
      final d = (local - _worldToLocal(verts[i])).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best >= 0 ? best : null;
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(floorPlanProvider);
    final verts = plan.vertices;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasSize = constraints.maxWidth;
        return InteractiveViewer(
          // One finger edits vertices (panEnabled off); two fingers zoom/pan.
          panEnabled: false,
          minScale: 1,
          maxScale: 6,
          boundaryMargin: const EdgeInsets.all(64),
          child: GestureDetector(
          onPanStart: (d) =>
              setState(() => _dragIndex = _nearestVertex(d.localPosition, verts)),
          onPanUpdate: (d) {
            final i = _dragIndex;
            if (i == null) return;
            final snapped = _snap(_localToWorld(d.localPosition), verts, i);
            final updated = [...verts]..[i] = snapped;
            ref.read(floorPlanProvider.notifier).state =
                plan.copyWith(vertices: updated);
          },
          onPanEnd: (_) => setState(() => _dragIndex = null),
          onTapUp: (d) {
            if (_nearestVertex(d.localPosition, verts) != null) return;
            _insertVertex(_localToWorld(d.localPosition), plan);
          },
          onLongPressStart: (d) {
            final i = _nearestVertex(d.localPosition, verts);
            if (i != null && verts.length > 3) {
              final updated = [...verts]..removeAt(i);
              ref.read(floorPlanProvider.notifier).state =
                  plan.copyWith(vertices: updated);
            }
          },
          child: CustomPaint(
            painter: _FloorPlanPainter(
              vertices: verts,
              scale: _scale,
              gridColor: scheme.onSurface.withValues(alpha: 0.12),
              lineColor: scheme.primary,
              fillColor: scheme.primary.withValues(alpha: 0.12),
              vertexColor: scheme.primary,
              labelColor: scheme.onSurface.withValues(alpha: 0.45),
            ),
            child: const SizedBox.expand(),
          ),
          ),
        );
      },
    );
  }

  /// Inserts [point] on the polygon edge nearest to it.
  void _insertVertex((double, double) point, FloorPlan plan) {
    final verts = plan.vertices;
    var bestEdge = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < verts.length; i++) {
      final a = verts[i];
      final b = verts[(i + 1) % verts.length];
      final d = _distanceToSegment(point, a, b);
      if (d < bestDist) {
        bestDist = d;
        bestEdge = i;
      }
    }
    final updated = [...verts]..insert(bestEdge + 1, point);
    ref.read(floorPlanProvider.notifier).state =
        plan.copyWith(vertices: updated);
  }

  double _distanceToSegment(
      (double, double) p, (double, double) a, (double, double) b) {
    final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) return math.sqrt(math.pow(p.$1 - a.$1, 2) + math.pow(p.$2 - a.$2, 2).toDouble());
    var t = ((p.$1 - a.$1) * dx + (p.$2 - a.$2) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final projX = a.$1 + t * dx, projY = a.$2 + t * dy;
    return math.sqrt(math.pow(p.$1 - projX, 2) + math.pow(p.$2 - projY, 2).toDouble());
  }
}

class _FloorPlanPainter extends CustomPainter {
  _FloorPlanPainter({
    required this.vertices,
    required this.scale,
    required this.gridColor,
    required this.lineColor,
    required this.fillColor,
    required this.vertexColor,
    required this.labelColor,
  });

  final List<(double, double)> vertices;
  final double scale;
  final Color gridColor;
  final Color lineColor;
  final Color fillColor;
  final Color vertexColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 1 m grid with metre labels along the top and left edges.
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: labelColor, fontSize: 9);
    for (var m = 0; m <= FloorPlanEditor.worldSize; m++) {
      final p = m * scale;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), grid);
      canvas.drawLine(Offset(0, p), Offset(size.width, p), grid);
      if (m < FloorPlanEditor.worldSize) {
        // X axis label (top) and Y axis label (left).
        _label(canvas, '${m}m', Offset(p + 2, 1), labelStyle);
        if (m > 0) _label(canvas, '${m}m', Offset(2, p + 1), labelStyle);
      }
    }

    // Tick "sticks" (crosses) at every 1 m crossing, to read the grid clearly.
    final tick = Paint()
      ..color = labelColor
      ..strokeWidth = 1.4;
    const t = 3.5;
    for (var gx = 0; gx <= FloorPlanEditor.worldSize; gx++) {
      for (var gy = 0; gy <= FloorPlanEditor.worldSize; gy++) {
        final cx = gx * scale, cy = gy * scale;
        canvas.drawLine(Offset(cx - t, cy), Offset(cx + t, cy), tick);
        canvas.drawLine(Offset(cx, cy - t), Offset(cx, cy + t), tick);
      }
    }

    if (vertices.length < 2) return;

    final path = Path()
      ..moveTo(vertices[0].$1 * scale, vertices[0].$2 * scale);
    for (var i = 1; i < vertices.length; i++) {
      path.lineTo(vertices[i].$1 * scale, vertices[i].$2 * scale);
    }
    path.close();

    canvas.drawPath(path, Paint()..color = fillColor);
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Edge length labels (metres) at each edge midpoint.
    final edgeLabelStyle = TextStyle(
      color: lineColor,
      fontSize: 10,
      fontWeight: FontWeight.w600,
    );
    for (var i = 0; i < vertices.length; i++) {
      final a = vertices[i];
      final b = vertices[(i + 1) % vertices.length];
      final len =
          math.sqrt(math.pow(b.$1 - a.$1, 2) + math.pow(b.$2 - a.$2, 2).toDouble());
      if (len < 0.1) continue;
      final mid = Offset(
        (a.$1 + b.$1) / 2 * scale,
        (a.$2 + b.$2) / 2 * scale,
      );
      _label(canvas, '${len.toStringAsFixed(1)}m',
          mid + const Offset(2, -6), edgeLabelStyle);
    }

    final vertexPaint = Paint()..color = vertexColor;
    for (final v in vertices) {
      canvas.drawCircle(Offset(v.$1 * scale, v.$2 * scale), 6, vertexPaint);
    }
  }

  void _label(Canvas canvas, String text, Offset at, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_FloorPlanPainter old) =>
      old.vertices != vertices || old.scale != scale;
}
