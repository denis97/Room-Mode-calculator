import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/acoustics/note_mapping.dart';

void main() {
  test('440 Hz maps to A4 / MIDI 69 with no detuning', () {
    final note = noteFromFrequency(440);
    expect(note.midi, 69);
    expect(note.name, 'A4');
    expect(note.cents, closeTo(0, 0.001));
  });

  test('middle C (≈261.63 Hz) maps to C4', () {
    final note = noteFromFrequency(261.63);
    expect(note.name, 'C4');
  });

  test('frequencyFromMidi is the inverse of midiFromFrequency', () {
    expect(frequencyFromMidi(69), closeTo(440, 0.001));
    expect(midiFromFrequency(880), closeTo(81, 0.001));
  });

  test('cents detuning is reported for an off-pitch frequency', () {
    // A slightly sharp A4.
    final note = noteFromFrequency(445);
    expect(note.name, 'A4');
    expect(note.cents, greaterThan(0));
  });
}
