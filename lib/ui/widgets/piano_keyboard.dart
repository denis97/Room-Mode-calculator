import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/tone_player.dart';
import '../../core/acoustics/mode.dart';
import '../../core/acoustics/note_mapping.dart';
import '../../state/room_providers.dart';
import '../mode_colors.dart';

/// A piano keyboard spanning the modal frequency range. Each calculated mode is
/// marked on the key whose pitch it matches (coloured by mode type). Tapping a
/// key plays its pitch; tapping a marked key also selects the lowest mode on
/// that key.
class PianoKeyboard extends ConsumerStatefulWidget {
  const PianoKeyboard({super.key});

  @override
  ConsumerState<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends ConsumerState<PianoKeyboard> {
  final TonePlayer _player = TonePlayer();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final modes = ref.watch(modesProvider);
    final maxFreq = ref.watch(maxFrequencyProvider);

    // Key range: from C below the lowest mode to the cutoff frequency.
    final lowMidi = modes.isEmpty
        ? 24
        : (midiFromFrequency(modes.first.frequency).floor() - 1);
    final highMidi = midiFromFrequency(maxFreq).ceil();
    final startMidi = (lowMidi ~/ 12) * 12; // snap to a C

    // Bucket modes by nearest MIDI note so we can mark and select them.
    final modesByMidi = <int, List<RoomMode>>{};
    for (final mode in modes) {
      final m = noteFromFrequency(mode.frequency).midi;
      modesByMidi.putIfAbsent(m, () => []).add(mode);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) => _handleTap(
            details.localPosition,
            Size(constraints.maxWidth, 110),
            startMidi,
            highMidi,
            modesByMidi,
            modes,
          ),
          child: CustomPaint(
            size: Size(constraints.maxWidth, 110),
            painter: _KeyboardPainter(
              startMidi: startMidi,
              endMidi: highMidi,
              modesByMidi: modesByMidi,
            ),
          ),
        );
      },
    );
  }

  void _handleTap(
    Offset pos,
    Size size,
    int startMidi,
    int endMidi,
    Map<int, List<RoomMode>> modesByMidi,
    List<RoomMode> modes,
  ) {
    final whiteCount = _whiteKeyCount(startMidi, endMidi);
    final whiteWidth = size.width / whiteCount;
    final midi = _midiAtX(pos.dx, startMidi, endMidi, whiteWidth, pos.dy, size);
    if (midi == null) return;

    final atKey = modesByMidi[midi];
    if (atKey != null && atKey.isNotEmpty) {
      // Select the lowest mode sitting on this key, and play that exact pitch.
      final mode = atKey.first;
      ref.read(selectedModeIndexProvider.notifier).state =
          modes.indexOf(mode);
      _player.playTone(mode.frequency);
    } else {
      _player.playTone(frequencyFromMidi(midi.toDouble()));
    }
  }

  static const _whiteSemitones = {0, 2, 4, 5, 7, 9, 11};

  bool _isWhite(int midi) => _whiteSemitones.contains(midi % 12);

  int _whiteKeyCount(int startMidi, int endMidi) {
    var n = 0;
    for (var m = startMidi; m <= endMidi; m++) {
      if (_isWhite(m)) n++;
    }
    return n;
  }

  /// Resolves which key (MIDI note) a tap landed on, honouring that black keys
  /// sit above and between white keys.
  int? _midiAtX(double x, int startMidi, int endMidi, double whiteWidth,
      double y, Size size) {
    // Black keys occupy the upper ~60% of the keyboard height.
    final inBlackZone = y < size.height * 0.6;
    var whiteIndex = 0;
    int? whiteHit;
    for (var m = startMidi; m <= endMidi; m++) {
      if (_isWhite(m)) {
        final left = whiteIndex * whiteWidth;
        if (x >= left && x < left + whiteWidth) whiteHit = m;
        // Check the black key drawn to the right of this white key.
        if (inBlackZone && _hasBlackAfter(m)) {
          final center = (whiteIndex + 1) * whiteWidth;
          final bw = whiteWidth * 0.6;
          if (x >= center - bw / 2 && x <= center + bw / 2) {
            return m + 1;
          }
        }
        whiteIndex++;
      }
    }
    return whiteHit;
  }

  bool _hasBlackAfter(int midi) {
    final pc = midi % 12;
    return pc == 0 || pc == 2 || pc == 5 || pc == 7 || pc == 9;
  }
}

class _KeyboardPainter extends CustomPainter {
  _KeyboardPainter({
    required this.startMidi,
    required this.endMidi,
    required this.modesByMidi,
  });

  final int startMidi;
  final int endMidi;
  final Map<int, List<RoomMode>> modesByMidi;

  static const _whiteSemitones = {0, 2, 4, 5, 7, 9, 11};
  bool _isWhite(int midi) => _whiteSemitones.contains(midi % 12);

  @override
  void paint(Canvas canvas, Size size) {
    var whiteCount = 0;
    for (var m = startMidi; m <= endMidi; m++) {
      if (_isWhite(m)) whiteCount++;
    }
    if (whiteCount == 0) return;
    final whiteWidth = size.width / whiteCount;

    final whitePaint = Paint()..color = const Color(0xFFF5F5F5);
    final borderPaint = Paint()
      ..color = Colors.black54
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final blackPaint = Paint()..color = const Color(0xFF1A1A1A);

    // White keys first.
    var whiteIndex = 0;
    final whitePositions = <int, double>{}; // midi -> left x
    for (var m = startMidi; m <= endMidi; m++) {
      if (!_isWhite(m)) continue;
      final left = whiteIndex * whiteWidth;
      final rect = Rect.fromLTWH(left, 0, whiteWidth, size.height);
      canvas.drawRect(rect, whitePaint);
      canvas.drawRect(rect, borderPaint);
      whitePositions[m] = left;
      _drawMarkers(canvas, m, left + whiteWidth / 2, size.height - 12,
          whiteWidth);
      whiteIndex++;
    }

    // Black keys on top.
    whiteIndex = 0;
    for (var m = startMidi; m <= endMidi; m++) {
      if (!_isWhite(m)) continue;
      final pc = m % 12;
      final hasBlack = pc == 0 || pc == 2 || pc == 5 || pc == 7 || pc == 9;
      if (hasBlack && m + 1 <= endMidi) {
        final center = (whiteIndex + 1) * whiteWidth;
        final bw = whiteWidth * 0.6;
        final rect = Rect.fromLTWH(
            center - bw / 2, 0, bw, size.height * 0.6);
        canvas.drawRect(rect, blackPaint);
        _drawMarkers(canvas, m + 1, center, size.height * 0.6 - 8, bw);
      }
      whiteIndex++;
    }
  }

  void _drawMarkers(
      Canvas canvas, int midi, double cx, double cy, double keyWidth) {
    final modes = modesByMidi[midi];
    if (modes == null || modes.isEmpty) return;
    // One dot per mode on the key, the dominant (lowest-order) type on top.
    final radius = (keyWidth * 0.18).clamp(3.0, 7.0);
    var y = cy;
    for (final mode in modes.take(3)) {
      canvas.drawCircle(
        Offset(cx, y),
        radius,
        Paint()..color = colorForModeType(mode.type),
      );
      y -= radius * 2 + 1;
    }
  }

  @override
  bool shouldRepaint(_KeyboardPainter old) =>
      old.startMidi != startMidi ||
      old.endMidi != endMidi ||
      old.modesByMidi != modesByMidi;
}
