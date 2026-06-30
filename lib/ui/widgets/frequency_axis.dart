import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustics/mode.dart';
import '../../state/room_providers.dart';
import '../mode_colors.dart';

/// Plots the calculated modes on a horizontal frequency axis. Each mode is a
/// vertical bar coloured by type and sized by relative strength. Tapping a bar
/// selects that mode (for the pressure map). The Schroeder frequency is drawn
/// as a dashed reference line.
class FrequencyAxis extends ConsumerWidget {
  const FrequencyAxis({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(modesProvider);
    final maxFreq = ref.watch(maxFrequencyProvider);
    final schroeder = ref.watch(schroederProvider);
    final selectedIndex = ref.watch(selectedModeIndexProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) {
            final i = _nearestModeIndex(
              modes,
              details.localPosition.dx,
              constraints.maxWidth,
              maxFreq,
            );
            ref.read(selectedModeIndexProvider.notifier).state = i;
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, 120),
            painter: _FrequencyAxisPainter(
              modes: modes,
              maxFreq: maxFreq,
              schroeder: schroeder,
              selectedIndex: selectedIndex,
              textColor: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        );
      },
    );
  }

  int? _nearestModeIndex(
    List<RoomMode> modes,
    double dx,
    double width,
    double maxFreq,
  ) {
    if (modes.isEmpty) return null;
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

class _FrequencyAxisPainter extends CustomPainter {
  _FrequencyAxisPainter({
    required this.modes,
    required this.maxFreq,
    required this.schroeder,
    required this.selectedIndex,
    required this.textColor,
  });

  final List<RoomMode> modes;
  final double maxFreq;
  final double schroeder;
  final int? selectedIndex;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    final baseY = size.height - 20;
    final axisPaint = Paint()
      ..color = textColor.withValues(alpha: 0.4)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), axisPaint);

    // Frequency gridlines + labels.
    final tick = _tickSpacing(maxFreq);
    final labelStyle = TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 10);
    for (var f = tick; f <= maxFreq; f += tick) {
      final x = f / maxFreq * size.width;
      canvas.drawLine(
        Offset(x, baseY),
        Offset(x, baseY + 4),
        axisPaint,
      );
      _text(canvas, '${f.round()}', Offset(x, baseY + 6), labelStyle,
          center: true);
    }

    // Schroeder reference line.
    if (schroeder > 0 && schroeder <= maxFreq) {
      final x = schroeder / maxFreq * size.width;
      final dashPaint = Paint()
        ..color = Colors.white70
        ..strokeWidth = 1;
      for (var y = 0.0; y < baseY; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 3), dashPaint);
      }
      _text(canvas, 'Schroeder ${schroeder.round()}Hz', Offset(x + 4, 2),
          TextStyle(color: Colors.white70, fontSize: 10));
    }

    // Mode bars.
    for (var i = 0; i < modes.length; i++) {
      final mode = modes[i];
      final x = mode.frequency / maxFreq * size.width;
      final barHeight = 18 + mode.strength / 4 * (baseY - 24);
      final selected = i == selectedIndex;
      final paint = Paint()
        ..color = colorForModeType(mode.type)
            .withValues(alpha: selected ? 1.0 : 0.85)
        ..strokeWidth = selected ? 3 : 1.6;
      canvas.drawLine(Offset(x, baseY), Offset(x, baseY - barHeight), paint);
      if (selected) {
        _text(
          canvas,
          '(${mode.p},${mode.q},${mode.r})  ${mode.frequency.toStringAsFixed(1)} Hz',
          Offset(x, baseY - barHeight - 14),
          TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.bold),
          center: true,
        );
      }
    }
  }

  double _tickSpacing(double maxFreq) {
    if (maxFreq <= 120) return 20;
    if (maxFreq <= 320) return 50;
    return 100;
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style,
      {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(_FrequencyAxisPainter old) =>
      old.modes != modes ||
      old.maxFreq != maxFreq ||
      old.schroeder != schroeder ||
      old.selectedIndex != selectedIndex;
}
