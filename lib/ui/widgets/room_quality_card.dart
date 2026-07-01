import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustics/room_ratios.dart';
import '../../state/room_providers.dart';

/// Summarizes how good the room's proportions are: the Schroeder frequency, the
/// Bonello criterion (with a ⅓-octave modal-density bar chart), and the room
/// ratio compared to well-known recommended ratios.
class RoomQualityCard extends ConsumerWidget {
  const RoomQualityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(roomProvider);
    final schroeder = ref.watch(schroederProvider);
    final bands = ref.watch(bonelloBandsProvider);
    final bonelloOk = bonelloSatisfied(bands);

    final proportion = RoomProportion.fromRoom(room);
    final (recommended, distance) = nearestRecommendedRatio(proportion);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room quality', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _metric(context, 'Schroeder frequency',
                '${schroeder.toStringAsFixed(0)} Hz'),
            _metric(context, 'Room ratio', proportion.toString()),
            _metric(
              context,
              'Nearest good ratio',
              '${recommended.name} '
                  '(1 : ${recommended.mid} : ${recommended.long}, Δ${distance.toStringAsFixed(2)})',
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  bonelloOk ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: bonelloOk ? Colors.green : Colors.orange,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    bonelloOk
                        ? 'Bonello criterion met — modal density rises smoothly'
                        : 'Bonello criterion not met — a ⅓-octave band dips in mode count',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 90,
              child: bands.isEmpty
                  ? const Center(child: Text('—'))
                  : CustomPaint(
                      painter: _BonelloPainter(
                        bands: bands,
                        barColor: theme.colorScheme.primary,
                        textColor: theme.colorScheme.onSurface,
                      ),
                      child: const SizedBox.expand(),
                    ),
            ),
            Text('Modes per ⅓-octave band',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _metric(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(label)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _BonelloPainter extends CustomPainter {
  _BonelloPainter({
    required this.bands,
    required this.barColor,
    required this.textColor,
  });

  final List<ThirdOctaveBand> bands;
  final Color barColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    var maxCount = 1;
    for (final b in bands) {
      if (b.modeCount > maxCount) maxCount = b.modeCount;
    }
    final baseY = size.height - 14;
    final slot = size.width / bands.length;
    final barW = slot * 0.7;
    final bar = Paint()..color = barColor;
    final labelStyle = TextStyle(
        color: textColor.withValues(alpha: 0.6), fontSize: 8);

    for (var i = 0; i < bands.length; i++) {
      final b = bands[i];
      final h = b.modeCount / maxCount * (baseY - 4);
      final x = i * slot + (slot - barW) / 2;
      canvas.drawRect(
        Rect.fromLTWH(x, baseY - h, barW, h),
        bar,
      );
      // Label every other band center to avoid crowding.
      if (i % 2 == 0) {
        final tp = TextPainter(
          text: TextSpan(
              text: b.centerHz.round().toString(), style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + barW / 2 - tp.width / 2, baseY + 2));
      }
    }
  }

  @override
  bool shouldRepaint(_BonelloPainter old) => old.bands != bands;
}
