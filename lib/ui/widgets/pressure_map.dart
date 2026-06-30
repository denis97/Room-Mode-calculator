import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustics/mode.dart';
import '../../core/acoustics/pressure_field.dart';
import '../../core/acoustics/room.dart';
import '../../state/room_providers.dart';

/// Shows the 2D standing-pressure pattern of the selected mode over a
/// horizontal slice of the room. Pressure is drawn as a diverging heatmap
/// (blue = negative, black ≈ node, red = positive). A slider moves the slice
/// height. Antinodes appear at the walls; nodal lines are where the pattern
/// passes through black.
class PressureMap extends ConsumerWidget {
  const PressureMap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(modesProvider);
    final index = ref.watch(selectedModeIndexProvider);
    final room = ref.watch(roomProvider);
    final sliceHeight = ref.watch(sliceHeightProvider);

    if (index == null || index >= modes.length) {
      return const Card(
        margin: EdgeInsets.all(12),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Select a mode to see its pressure pattern'),
          ),
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
              'Pressure — mode (${mode.p},${mode.q},${mode.r})  '
              '${mode.frequency.toStringAsFixed(1)} Hz  ${mode.type.label}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Top-down slice • length → horizontal, width → vertical',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: room.length / room.width,
              child: FutureBuilder<ui.Image>(
                future: _renderImage(mode, room, sliceHeight),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return CustomPaint(
                    painter: _ImagePainter(snapshot.data!),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
            Row(
              children: [
                const Text('Slice height'),
                Expanded(
                  child: Slider(
                    value: sliceHeight.clamp(0, room.height),
                    min: 0,
                    max: room.height,
                    onChanged: (v) =>
                        ref.read(sliceHeightProvider.notifier).state = v,
                  ),
                ),
                Text('${sliceHeight.toStringAsFixed(2)} m'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<ui.Image> _renderImage(
      RoomMode mode, Room room, double sliceHeight) async {
    const cols = 96;
    const rows = 96;
    final grid = samplePressureSlice(mode, room,
        z: sliceHeight, cols: cols, rows: rows);

    final pixels = Uint8List(cols * rows * 4);
    for (var i = 0; i < grid.values.length; i++) {
      final color = _divergingColor(grid.values[i]);
      final o = i * 4;
      pixels[o] = color.$1; // R
      pixels[o + 1] = color.$2; // G
      pixels[o + 2] = color.$3; // B
      pixels[o + 3] = 255; // A
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      cols,
      rows,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Maps a signed pressure value in [-1, 1] to a blue–black–red diverging
  /// colour. Magnitude near zero (nodes) renders dark.
  (int, int, int) _divergingColor(double v) {
    final m = v.abs().clamp(0.0, 1.0);
    if (v >= 0) {
      return ((m * 255).round(), (m * 60).round(), (m * 40).round());
    } else {
      return ((m * 40).round(), (m * 80).round(), (m * 255).round());
    }
  }
}

class _ImagePainter extends CustomPainter {
  _ImagePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
        0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Offset.zero & size;
    canvas.drawImageRect(
      image,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_ImagePainter old) => old.image != image;
}
