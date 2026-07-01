import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/custom_room_providers.dart';

/// An interactive top-down editor for the room's floor polygon.
///
/// - **Drag** a vertex to move it.
/// - **Tap** an empty spot to insert a vertex on the nearest edge.
/// - **Long-press** near a vertex to delete it (minimum three remain).
///
/// Coordinates are metres on a fixed [worldSize]×[worldSize] field with a 1 m
/// grid; edits write straight to [floorPlanProvider].
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
        return GestureDetector(
          onPanStart: (d) =>
              setState(() => _dragIndex = _nearestVertex(d.localPosition, verts)),
          onPanUpdate: (d) {
            final i = _dragIndex;
            if (i == null) return;
            final updated = [...verts]..[i] = _localToWorld(d.localPosition);
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
