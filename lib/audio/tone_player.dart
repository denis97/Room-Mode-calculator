import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Plays short sine-wave tones so the user can "hear" a room mode's pitch, the
/// way amroc lets you hear the tune of a mode.
///
/// Tones are synthesised on the fly as 16-bit PCM WAV byte buffers and played
/// through [audioplayers]'s [BytesSource], so no audio assets are bundled.
class TonePlayer {
  TonePlayer({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  static const int _sampleRate = 44100;

  /// Plays a [frequency] (Hz) sine tone for [duration]. A short fade in/out
  /// avoids clicks at the boundaries.
  Future<void> playTone(
    double frequency, {
    Duration duration = const Duration(milliseconds: 700),
    double amplitude = 0.6,
  }) async {
    final wav = _synthesizeWav(frequency, duration, amplitude);
    await _player.stop();
    await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();

  Uint8List _synthesizeWav(
    double frequency,
    Duration duration,
    double amplitude,
  ) {
    final sampleCount =
        (_sampleRate * duration.inMilliseconds / 1000).round();
    final fadeSamples = math.min(sampleCount ~/ 10, _sampleRate ~/ 100);

    final bytesPerSample = 2;
    final dataSize = sampleCount * bytesPerSample;
    final buffer = ByteData(44 + dataSize);

    // ---- WAV header (PCM, mono, 16-bit) ----
    _writeAscii(buffer, 0, 'RIFF');
    buffer.setUint32(4, 36 + dataSize, Endian.little);
    _writeAscii(buffer, 8, 'WAVE');
    _writeAscii(buffer, 12, 'fmt ');
    buffer.setUint32(16, 16, Endian.little); // fmt chunk size
    buffer.setUint16(20, 1, Endian.little); // audio format = PCM
    buffer.setUint16(22, 1, Endian.little); // channels = mono
    buffer.setUint32(24, _sampleRate, Endian.little);
    buffer.setUint32(28, _sampleRate * bytesPerSample, Endian.little); // byte rate
    buffer.setUint16(32, bytesPerSample, Endian.little); // block align
    buffer.setUint16(34, 16, Endian.little); // bits per sample
    _writeAscii(buffer, 36, 'data');
    buffer.setUint32(40, dataSize, Endian.little);

    // ---- PCM samples ----
    for (var i = 0; i < sampleCount; i++) {
      var gain = amplitude;
      if (i < fadeSamples) {
        gain *= i / fadeSamples;
      } else if (i > sampleCount - fadeSamples) {
        gain *= (sampleCount - i) / fadeSamples;
      }
      final sample =
          math.sin(2 * math.pi * frequency * i / _sampleRate) * gain;
      final value = (sample * 32767).clamp(-32768, 32767).round();
      buffer.setInt16(44 + i * bytesPerSample, value, Endian.little);
    }

    return buffer.buffer.asUint8List();
  }

  void _writeAscii(ByteData data, int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
}
