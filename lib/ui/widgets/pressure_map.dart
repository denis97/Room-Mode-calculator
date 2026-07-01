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
///
/// The heatmap image is cached and only re-rendered when the mode, room, or
/// slice height actually changes — so unrelated rebuilds (e.g. editing the
/// room while another mode is selected) don't trigger a re-decode.
class PressureMap extends ConsumerStatefulWidget {
  const PressureMap({super.key});

  @override
  ConsumerState<PressureMap> createState() => _PressureMapState();
}

class _PressureMapState extends ConsumerState<PressureMap> {
  ui.Image? _image;
  String? _renderedKey;
  String? _pendingKey;

  @override
  Widget build(BuildContext context) {
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
    final key = _cacheKey(mode, room, sliceHeight);
    if (key != _renderedKey && key != _pendingKey) {
      _pendingKey = key;
      _render(mode, room, sliceHeight, key);
    }

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
              child: _image == null
                  ? const Center(child: CircularProgressIndicator())
                  : CustomPaint(
                      painter: _ImagePainter(_image!),
                      child: const SizedBox.expand(),
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

  String _cacheKey(RoomMode mode, Room room, double sliceHeight) =>
      '${mode.p},${mode.q},${mode.r}|'
      '${room.length},${room.width},${room.height}|'
      '${sliceHeight.toStringAsFixed(3)}';

  Future<void> _render(
    RoomMode mode,
    Room room,
    double sliceHeight,
    String key,
  ) async {
    final image = await _renderImage(mode, room, sliceHeight);
    if (!mounted) return;
    // Drop the result if a newer render has since been requested.
    if (key != _pendingKey) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _renderedKey = key;
    });
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

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
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
