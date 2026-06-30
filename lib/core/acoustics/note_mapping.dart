import 'dart:math' as math;

/// Maps acoustic frequencies to musical pitch so modes can be shown on a piano
/// keyboard and "heard" as notes, the way amroc does.

const List<String> _noteNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// The (possibly fractional) MIDI note number for a frequency in Hz.
/// A4 = 440 Hz maps to MIDI 69.
double midiFromFrequency(double frequency) {
  return 69 + 12 * (math.log(frequency / 440.0) / math.ln2);
}

/// The frequency in Hz for a (possibly fractional) MIDI note number.
double frequencyFromMidi(double midi) {
  return 440.0 * math.pow(2, (midi - 69) / 12.0).toDouble();
}

/// A musical note: the nearest semitone for a frequency, its name with octave
/// (e.g. "A4"), and how many cents sharp (+) or flat (-) the frequency sits
/// relative to that semitone.
class Note {
  const Note({
    required this.midi,
    required this.name,
    required this.cents,
  });

  /// Nearest integer MIDI note.
  final int midi;

  /// Note name including octave, e.g. "C#3".
  final String name;

  /// Detuning from the named note in cents, range (-50, +50].
  final double cents;
}

Note noteFromFrequency(double frequency) {
  final exactMidi = midiFromFrequency(frequency);
  final nearest = exactMidi.round();
  final cents = (exactMidi - nearest) * 100;
  // MIDI 0 is C-1, so octave = midi ~/ 12 - 1.
  final octave = (nearest ~/ 12) - 1;
  final name = '${_noteNames[nearest % 12]}$octave';
  return Note(midi: nearest, name: name, cents: cents);
}
