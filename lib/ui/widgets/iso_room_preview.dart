import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_theme.dart';

/// A small isometric wireframe preview of the cuboid's proportions, with
/// dimension labels on the length/width/height edges — the setup screen's
/// at-a-glance sanity check before computing modes.
class IsoRoomPreview extends StatelessWidget {
  const IsoRoomPreview({
    super.key,
    required this.length,
    required this.width,
    required this.height,
  });

  final double length;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _IsoBoxPainter(length: length, width: width, height: height),
      child: const SizedBox.expand(),
    );
  }
}

class _IsoBoxPainter extends CustomPainter {
  _IsoBoxPainter({
    required this.length,
    required this.width,
    required this.height,
  });

  final double length;
  final double width;
  final double height;

  static const double _theta = 0.7;
  static const double _elevation = 0.42;

  Offset _iso(double x, double y, double z, double cx, double cy, double cz) {
    x -= cx;
    y -= cy;
    z -= cz;
    final x1 = x * math.cos(_theta) - y * math.sin(_theta);
    final y1 = x * math.sin(_theta) + y * math.cos(_theta);
    final z1 = z;
    return Offset(
      x1,
      z1 * math.cos(_elevation) - y1 * math.sin(_elevation),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final l = length, w = width, h = height;
    final cx = l / 2, cy = w / 2, cz = h / 2;

    final corners = [
      [0.0, 0.0, 0.0], [l, 0.0, 0.0], [l, w, 0.0], [0.0, w, 0.0],
      [0.0, 0.0, h], [l, 0.0, h], [l, w, h], [0.0, w, h],
    ].map((c) => _iso(c[0], c[1], c[2], cx, cy, cz)).toList();

    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (final p in corners) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    const pad = 30.0;
    final scale = math.min(
      (size.width - pad * 2) / (maxX - minX),
      (size.height - pad * 2) / (maxY - minY),
    );
    final ox = size.width / 2 - (minX + maxX) / 2 * scale;
    final oy = size.height / 2 + (minY + maxY) / 2 * scale;
    Offset s(Offset p) => Offset(ox + p.dx * scale, oy - p.dy * scale);

    const edges = [
      [0, 1], [1, 2], [2, 3], [3, 0],
      [4, 5], [5, 6], [6, 7], [7, 4],
      [0, 4], [1, 5], [2, 6], [3, 7],
    ];

    final floorPath = Path()
      ..moveTo(s(corners[0]).dx, s(corners[0]).dy)
      ..lineTo(s(corners[1]).dx, s(corners[1]).dy)
      ..lineTo(s(corners[2]).dx, s(corners[2]).dy)
      ..lineTo(s(corners[3]).dx, s(corners[3]).dy)
      ..close();
    canvas.drawPath(
        floorPath, Paint()..color = AppColors.accent.withValues(alpha: 0.07));

    final edgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 1.4;
    for (final e in edges) {
      canvas.drawLine(s(corners[e[0]]), s(corners[e[1]]), edgePaint);
    }

    final labelStyle = monoStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent);
    void label(String text, Offset at) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    Offset mid(int a, int b) =>
        Offset.lerp(s(corners[a]), s(corners[b]), 0.5)!;
    label('L ${l.toStringAsFixed(1)}', mid(0, 1) + const Offset(0, 14));
    label('W ${w.toStringAsFixed(1)}', mid(1, 2) + const Offset(20, 0));
    label('H ${h.toStringAsFixed(1)}', mid(0, 4) + const Offset(-18, 0));
  }

  @override
  bool shouldRepaint(_IsoBoxPainter old) =>
      old.length != length || old.width != width || old.height != height;
}
