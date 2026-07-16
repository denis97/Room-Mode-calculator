import 'package:flutter/material.dart';

import '../../core/numeric/modal_analysis.dart';
import '../app_theme.dart';

/// Plots a solved custom room's modes on a horizontal frequency axis, the
/// same visual language as the cuboid [FrequencyAxis] but for
/// [ComputedMode]s -- which carry a frequency and a pressure field, not the
/// analytical (p,q,r)/type breakdown, so every bar is drawn the same size
/// and color rather than fabricating a strength/type that the solver never
/// computed. Tapping a bar selects that mode.
class ComputedModeAxis extends StatelessWidget {
  const ComputedModeAxis({
    super.key,
    required this.modes,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<ComputedMode> modes;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (modes.isEmpty) {
      return const SizedBox(
        height: 92,
        child: Center(
          child: Text('No modes', style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    final maxFreq = modes.last.frequency;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            onSelect(_nearestIndex(details.localPosition.dx, constraints.maxWidth, maxFreq));
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, 92),
            painter: _ComputedAxisPainter(
              modes: modes,
              maxFreq: maxFreq,
              selectedIndex: selectedIndex,
            ),
          ),
        );
      },
    );
  }

  int _nearestIndex(double dx, double width, double maxFreq) {
    final freq = dx / width * maxFreq;
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < modes.length; i++) {
      final d = (modes[i].frequency - freq).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }
}

class _ComputedAxisPainter extends CustomPainter {
  _ComputedAxisPainter({
    required this.modes,
    required this.maxFreq,
    required this.selectedIndex,
  });

  final List<ComputedMode> modes;
  final double maxFreq;
  final int? selectedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final baseY = size.height - 20;
    final axisPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.3;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), axisPaint);

    final tick = _tickSpacing(maxFreq);
    final labelStyle = monoStyle(fontSize: 9, color: AppColors.textFaint);
    for (var f = 0.0; f <= maxFreq; f += tick) {
      final x = f / maxFreq * size.width;
      canvas.drawLine(Offset(x, baseY), Offset(x, baseY + 4), axisPaint);
      _text(canvas, '${f.round()}', Offset(x, baseY + 6), labelStyle, center: true);
    }

    for (var i = 0; i < modes.length; i++) {
      final m = modes[i];
      final x = maxFreq > 0 ? m.frequency / maxFreq * size.width : 0.0;
      const barHeight = 30.0;
      final selected = i == selectedIndex;
      final paint = Paint()
        ..color = AppColors.accent.withValues(alpha: selected ? 1.0 : 0.75)
        ..strokeWidth = selected ? 3 : 1.6;
      canvas.drawLine(Offset(x, baseY), Offset(x, baseY - barHeight), paint);
      if (selected) {
        canvas.drawCircle(Offset(x, baseY - barHeight), 3, Paint()..color = AppColors.accent);
        _text(
          canvas,
          '${m.frequency.toStringAsFixed(1)} Hz',
          Offset(x, baseY - barHeight - 14),
          monoStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
          center: true,
        );
      }
    }
  }

  double _tickSpacing(double maxFreq) {
    if (maxFreq <= 60) return 10;
    if (maxFreq <= 120) return 20;
    if (maxFreq <= 320) return 50;
    return 100;
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(_ComputedAxisPainter old) =>
      old.modes != modes || old.maxFreq != maxFreq || old.selectedIndex != selectedIndex;
}
