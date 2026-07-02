import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustics/mode.dart';
import '../../core/acoustics/pressure_field.dart';
import '../../core/acoustics/room.dart';
import '../../state/room_providers.dart';
import '../app_theme.dart';

/// Shows the 2D standing-pressure pattern of the selected mode over a
/// horizontal slice of the room. Pressure is drawn as the shared diverging
/// heatmap (cyan = negative, near-black ≈ node, pink-red = positive). A
/// slider moves the slice height. Antinodes appear at the walls; nodal lines
/// are where the pattern passes through black.
///
/// The heatmap image is cached and only re-rendered when the mode, room, or
/// slice height actually changes — so unrelated rebuilds (e.g. editing the
/// room while another mode is selected) don't trigger a re-decode.
///
/// Headless: renders content only, no card chrome.
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
      return const Center(
        child: Text('Select a mode to see its pressure pattern',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }

    final mode = modes[index];
    final key = _cacheKey(mode, room, sliceHeight);
    if (key != _renderedKey && key != _pendingKey) {
      _pendingKey = key;
      _render(mode, room, sliceHeight, key);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Top-down slice — length → horizontal, width → vertical',
          style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
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
            const Text('Slice height',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Expanded(
              child: Slider(
                value: sliceHeight.clamp(0, room.height),
                min: 0,
                max: room.height,
                onChanged: (v) =>
                    ref.read(sliceHeightProvider.notifier).state = v,
              ),
            ),
            Text('${sliceHeight.toStringAsFixed(2)} m',
                style: monoStyle(fontSize: 12)),
          ],
        ),
      ],
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
      final color = fieldColor(grid.values[i]);
      final o = i * 4;
      pixels[o] = (color.r * 255).round(); // R
      pixels[o + 1] = (color.g * 255).round(); // G
      pixels[o + 2] = (color.b * 255).round(); // B
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
