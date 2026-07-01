import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geometry/voxel_grid.dart';
import '../../core/numeric/modal_analysis.dart';
import '../../state/custom_room_providers.dart';

/// A top-down interior cross-section of the selected computed mode at an
/// adjustable height — shows the pressure pattern *inside* an arbitrary room
/// (cells outside the footprint are transparent), complementing the
/// surface-only 3D view.
class CustomModeSliceView extends ConsumerStatefulWidget {
  const CustomModeSliceView({
    super.key,
    required this.grid,
    required this.mode,
    required this.maxHeight,
  });

  final VoxelGrid grid;
  final ComputedMode mode;
  final double maxHeight;

  @override
  ConsumerState<CustomModeSliceView> createState() =>
      _CustomModeSliceViewState();
}

class _CustomModeSliceViewState extends ConsumerState<CustomModeSliceView> {
  ui.Image? _image;
  String? _renderedKey;
  String? _pendingKey;

  @override
  Widget build(BuildContext context) {
    final sliceHeight = ref.watch(customSliceHeightProvider);
    final key = '${identityHashCode(widget.mode)}|${sliceHeight.toStringAsFixed(3)}';
    if (key != _renderedKey && key != _pendingKey) {
      _pendingKey = key;
      _render(sliceHeight, key);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: widget.grid.nx / widget.grid.ny,
          child: _image == null
              ? const Center(child: CircularProgressIndicator())
              : CustomPaint(
                  painter: _SlicePainter(_image!),
                  child: const SizedBox.expand(),
                ),
        ),
        Row(
          children: [
            const Text('Slice height'),
            Expanded(
              child: Slider(
                value: sliceHeight.clamp(0, widget.maxHeight),
                min: 0,
                max: widget.maxHeight,
                onChanged: (v) =>
                    ref.read(customSliceHeightProvider.notifier).state = v,
              ),
            ),
            Text('${sliceHeight.toStringAsFixed(2)} m'),
          ],
        ),
      ],
    );
  }

  Future<void> _render(double sliceHeight, String key) async {
    final slice = horizontalSlice(widget.grid, widget.mode.field, sliceHeight);
    final image = await _sliceToImage(slice);
    if (!mounted) return;
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

  Future<ui.Image> _sliceToImage(ModeSlice slice) async {
    final pixels = Uint8List(slice.nx * slice.ny * 4);
    for (var j = 0; j < slice.ny; j++) {
      for (var i = 0; i < slice.nx; i++) {
        final o = (j * slice.nx + i) * 4;
        final v = slice.at(i, j);
        if (v == null) {
          pixels[o + 3] = 0; // outside the room → transparent
          continue;
        }
        final (r, g, b) = _divergingColor(v / slice.maxAbs);
        pixels[o] = r;
        pixels[o + 1] = g;
        pixels[o + 2] = b;
        pixels[o + 3] = 255;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      slice.nx,
      slice.ny,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  (int, int, int) _divergingColor(double v) {
    final m = v.abs().clamp(0.0, 1.0);
    if (v >= 0) {
      return ((m * 255).round(), (m * 60).round(), (m * 40).round());
    }
    return ((m * 40).round(), (m * 80).round(), (m * 255).round());
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }
}

class _SlicePainter extends CustomPainter {
  _SlicePainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.none,
    );
  }

  @override
  bool shouldRepaint(_SlicePainter old) => old.image != image;
}
