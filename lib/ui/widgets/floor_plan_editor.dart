import 'dart:async';
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
/// - **Two fingers** to pan and pinch-zoom the view.
///
/// One-finger vertex editing and two-finger pan/zoom are handled with raw
/// pointer tracking (not nested `GestureDetector`s) because a single-pointer
/// drag recognizer nested inside a pan/zoom recognizer wins the gesture arena
/// on the first finger down, before a second finger ever gets a chance to
/// turn it into a scale gesture -- that's what silently broke pinch-to-zoom.
///
/// Coordinates are metres. The view starts showing a [viewSpan]×[viewSpan]
/// field with a 1 m grid marked by tick crosses, but the field itself
/// extends out to [maxExtent] -- pan and zoom out to reach the rest of it,
/// it's not a hard boundary around the room you started with. Edits write
/// straight to [floorPlanProvider].
class FloorPlanEditor extends ConsumerStatefulWidget {
  const FloorPlanEditor({super.key, this.interactive = true});

  /// Metres visible across the *width* at 1x zoom -- matches
  /// `editorWorldSize` in custom_room_providers.dart, which centers new
  /// shapes/presets in this same initial frame.
  static const double viewSpan = 8.0;

  /// Outer clamp on vertex coordinates and how far the grid is drawn. Much
  /// bigger than [viewSpan] so panning/zooming out reveals real extra room
  /// to work in, not just the initially-visible square.
  static const double maxExtent = 32.0;

  /// When false, renders a static read-only preview with no gesture
  /// handling at all -- for a small thumbnail where the caller supplies its
  /// own tap handler (e.g. "tap to expand").
  final bool interactive;

  @override
  ConsumerState<FloorPlanEditor> createState() => _FloorPlanEditorState();
}

class _FloorPlanEditorState extends ConsumerState<FloorPlanEditor> {
  double _canvasWidth = 1;
  double _canvasHeight = 1;

  // ---- pan/zoom view transform (screen = world*_scale*_viewScale + _viewOffset) ----
  double _viewScale = 1.0;
  Offset _viewOffset = const Offset(0, 0);
  bool _isInitialized = false;
  static const double _minZoom = 0.4;
  static const double _maxZoom = 6.0;

  // ---- raw pointer tracking ----
  final Map<int, Offset> _pointers = {};

  int? _primaryPointer;
  Offset? _downPosition;
  bool _movedPastSlop = false;
  bool _longPressHandled = false;
  int? _dragIndex;
  Timer? _longPressTimer;
  static const double _tapSlop = 8.0;
  static const Duration _longPressDuration = Duration(milliseconds: 500);

  bool _multiTouchActive = false;
  double _gestureStartDistance = 0;
  Offset _gestureStartMidpoint = Offset.zero;
  double _gestureStartViewScale = 1;
  Offset _gestureStartViewOffset = Offset.zero;

  double get _scale => _canvasWidth / FloorPlanEditor.viewSpan;

  Offset _worldToLocal((double, double) v) =>
      Offset(v.$1 * _scale, v.$2 * _scale);

  (double, double) _localToWorld(Offset p) => (
        (p.dx / _scale).clamp(0.0, FloorPlanEditor.maxExtent),
        (p.dy / _scale).clamp(0.0, FloorPlanEditor.maxExtent),
      );

  Offset _worldToScreen((double, double) v) =>
      _worldToLocal(v) * _viewScale + _viewOffset;

  (double, double) _screenToWorld(Offset p) =>
      _localToWorld((p - _viewOffset) / _viewScale);

  static const double _snapGrid = 0.25; // metres

  /// Snaps a dragged vertex to a 0.25 m grid and aligns it to a neighbour's
  /// row or column when close, so edges lock to horizontal/vertical (90°) --
  /// but only *magnetically*, within a small capture radius around each
  /// grid line/neighbour axis. Outside that radius the vertex tracks the
  /// finger continuously instead of jumping between grid points every
  /// frame. Both radii shrink as you zoom in, so a closer zoom gives finer,
  /// less-magnetic control over exactly where a vertex lands.
  (double, double) _snap(
      (double, double) p, List<(double, double)> verts, int index) {
    final gridTol = (_snapGrid * 0.3 / _viewScale).clamp(0.01, _snapGrid * 0.3);
    final alignTol = (0.4 / _viewScale).clamp(0.03, 0.4);

    var sx = p.$1, sy = p.$2;
    final gx = (p.$1 / _snapGrid).round() * _snapGrid;
    final gy = (p.$2 / _snapGrid).round() * _snapGrid;
    if ((p.$1 - gx).abs() < gridTol) sx = gx;
    if ((p.$2 - gy).abs() < gridTol) sy = gy;

    final n = verts.length;
    final prev = verts[(index - 1 + n) % n];
    final next = verts[(index + 1) % n];
    if ((sx - prev.$1).abs() < alignTol) {
      sx = prev.$1;
    } else if ((sx - next.$1).abs() < alignTol) {
      sx = next.$1;
    }
    if ((sy - prev.$2).abs() < alignTol) {
      sy = prev.$2;
    } else if ((sy - next.$2).abs() < alignTol) {
      sy = next.$2;
    }
    final w = FloorPlanEditor.maxExtent;
    return (sx.clamp(0.0, w), sy.clamp(0.0, w));
  }

  /// Hit-tests in screen space (post pan/zoom) so the touch target stays a
  /// constant finger-sized radius regardless of zoom level.
  int? _nearestVertexScreen(Offset screenPoint, List<(double, double)> verts) {
    var best = -1;
    var bestDist = 24.0; // px hit radius
    for (var i = 0; i < verts.length; i++) {
      final d = (screenPoint - _worldToScreen(verts[i])).distance;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best >= 0 ? best : null;
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  // ---------------- single-finger: vertex drag / tap-insert / long-press-delete ----------------

  void _beginSingleFinger(Offset localPosition) {
    final plan = ref.read(floorPlanProvider);
    _downPosition = localPosition;
    _movedPastSlop = false;
    _longPressHandled = false;
    _dragIndex = _nearestVertexScreen(localPosition, plan.vertices);
    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      if (_movedPastSlop || _downPosition == null) return;
      final cur = ref.read(floorPlanProvider);
      final i = _nearestVertexScreen(_downPosition!, cur.vertices);
      if (i != null && cur.vertices.length > 3) {
        final updated = [...cur.vertices]..removeAt(i);
        ref.read(floorPlanProvider.notifier).state =
            cur.copyWith(vertices: updated);
        _dragIndex = null;
      }
      // Mark the long-press as handled either way -- even a deletion that
      // didn't qualify (e.g. already at the 3-vertex minimum) shouldn't
      // fall through to inserting a new vertex on release.
      _longPressHandled = true;
    });
  }

  void _updateSingleFinger(Offset localPosition) {
    if (_downPosition == null) return;
    if ((localPosition - _downPosition!).distance > _tapSlop) {
      _movedPastSlop = true;
      _longPressTimer?.cancel();
    }
    final i = _dragIndex;
    if (i == null) return;
    final plan = ref.read(floorPlanProvider);
    final verts = plan.vertices;
    final snapped = _snap(_screenToWorld(localPosition), verts, i);
    final updated = [...verts]..[i] = snapped;
    ref.read(floorPlanProvider.notifier).state =
        plan.copyWith(vertices: updated);
  }

  void _endSingleFinger({bool tapIfUnmoved = true}) {
    _longPressTimer?.cancel();
    if (tapIfUnmoved &&
        _dragIndex == null &&
        !_movedPastSlop &&
        !_longPressHandled &&
        _downPosition != null) {
      final plan = ref.read(floorPlanProvider);
      if (_nearestVertexScreen(_downPosition!, plan.vertices) == null) {
        _insertVertex(_screenToWorld(_downPosition!), plan);
      }
    }
    _dragIndex = null;
    _primaryPointer = null;
    _downPosition = null;
    _movedPastSlop = false;
    _longPressHandled = false;
  }

  // ---------------- two-finger: pan + pinch-zoom ----------------

  void _beginMultiTouch() {
    final pts = _pointers.values.toList();
    if (pts.length < 2) return;
    _multiTouchActive = true;
    _gestureStartDistance = math.max((pts[0] - pts[1]).distance, 1.0);
    _gestureStartMidpoint = Offset.lerp(pts[0], pts[1], 0.5)!;
    _gestureStartViewScale = _viewScale;
    _gestureStartViewOffset = _viewOffset;
  }

  void _updateMultiTouch() {
    if (!_multiTouchActive) {
      _beginMultiTouch();
      return;
    }
    final pts = _pointers.values.toList();
    if (pts.length < 2) return;
    final dist = math.max((pts[0] - pts[1]).distance, 1.0);
    final midpoint = Offset.lerp(pts[0], pts[1], 0.5)!;
    final newScale = (_gestureStartViewScale * (dist / _gestureStartDistance))
        .clamp(_minZoom, _maxZoom);
    // Keep the pre-zoom canvas point under the gesture's start midpoint
    // fixed under the *current* midpoint -- this gives pinch-to-zoom
    // centered on the fingers, plus panning for free (a pure 2-finger drag
    // has dist ~= startDist, so newScale ~= startScale and the offset just
    // tracks the midpoint's movement).
    final k = (_gestureStartMidpoint - _gestureStartViewOffset) /
        _gestureStartViewScale;
    final newOffset = _clampOffset(midpoint - k * newScale, newScale);
    setState(() {
      _viewScale = newScale;
      _viewOffset = newOffset;
    });
  }

  void _endMultiTouch() {
    _multiTouchActive = false;
  }

  Offset _clampOffset(Offset offset, double scale) {
    const margin = 64.0;
    final contentW = _canvasWidth * scale;
    final contentH = _canvasHeight * scale;
    final minDx = math.min(_canvasWidth - contentW - margin, margin);
    final maxDx = math.max(_canvasWidth - contentW - margin, margin);
    final minDy = math.min(_canvasHeight - contentH - margin, margin);
    final maxDy = math.max(_canvasHeight - contentH - margin, margin);
    return Offset(
      offset.dx.clamp(minDx, maxDx),
      offset.dy.clamp(minDy, maxDy),
    );
  }

  // ---------------- raw pointer routing ----------------

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 1) {
      _primaryPointer = event.pointer;
      _beginSingleFinger(event.localPosition);
    } else if (_pointers.length == 2) {
      _endSingleFinger(tapIfUnmoved: false);
      _beginMultiTouch();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _updateMultiTouch();
      return;
    }
    if (event.pointer != _primaryPointer) return;
    _updateSingleFinger(event.localPosition);
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_multiTouchActive) {
      if (_pointers.length < 2) _endMultiTouch();
      return;
    }
    if (event.pointer == _primaryPointer) {
      _endSingleFinger();
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.watch(floorPlanProvider);
    final verts = plan.vertices;
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        _canvasWidth = constraints.maxWidth;
        _canvasHeight = constraints.maxHeight;

        // Center the view on the room's bounding box on first render
        if (!_isInitialized && verts.isNotEmpty && _canvasWidth > 1) {
          _isInitialized = true;
          var minX = double.infinity, minY = double.infinity;
          var maxX = -double.infinity, maxY = -double.infinity;
          for (final (x, y) in verts) {
            minX = math.min(minX, x);
            maxX = math.max(maxX, x);
            minY = math.min(minY, y);
            maxY = math.max(maxY, y);
          }
          final centerX = (minX + maxX) / 2;
          final centerY = (minY + maxY) / 2;
          // Pan so the room center aligns with the viewport center
          _viewOffset = Offset(
            (FloorPlanEditor.viewSpan / 2 - centerX) * _scale,
            (FloorPlanEditor.viewSpan / 2 - centerY) * _scale,
          );
        }

        final content = ClipRect(
          child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(_viewOffset.dx, _viewOffset.dy, 0, 1)
              ..scaleByDouble(_viewScale, _viewScale, 1, 1),
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

        if (!widget.interactive) return content;

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerUp,
          child: content,
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
    for (var m = 0; m <= FloorPlanEditor.maxExtent; m++) {
      final p = m * scale;
      canvas.drawLine(Offset(p, 0), Offset(p, size.height), grid);
      canvas.drawLine(Offset(0, p), Offset(size.width, p), grid);
      if (m < FloorPlanEditor.maxExtent) {
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
    for (var gx = 0; gx <= FloorPlanEditor.maxExtent; gx++) {
      for (var gy = 0; gy <= FloorPlanEditor.maxExtent; gy++) {
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
