import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/acoustics/mode.dart';
import 'package:room_mode_calculator/core/acoustics/mode_calculator.dart';
import 'package:room_mode_calculator/core/acoustics/room.dart';

void main() {
  // A 5×4×3 m room at exactly c = 343 m/s (≈ 20.07 °C) gives convenient
  // hand-computable anchor frequencies.
  const room = Room(
    length: 5,
    width: 4,
    height: 3,
    temperatureC: 20.0703,
  );

  RoomMode modeOf(List<RoomMode> modes, int p, int q, int r) =>
      modes.firstWhere((m) => m.p == p && m.q == q && m.r == r);

  test('axial mode frequencies match the analytical formula', () {
    final modes = calculateRoomModes(room, maxFrequencyHz: 300);

    // f(1,0,0) = c / (2L) = 343 / 10 = 34.3 Hz
    expect(modeOf(modes, 1, 0, 0).frequency, closeTo(34.3, 0.05));
    // f(0,1,0) = c / (2W) = 343 / 8 = 42.875 Hz
    expect(modeOf(modes, 0, 1, 0).frequency, closeTo(42.875, 0.05));
    // f(0,0,1) = c / (2H) = 343 / 6 ≈ 57.17 Hz
    expect(modeOf(modes, 0, 0, 1).frequency, closeTo(57.17, 0.05));
  });

  test('tangential mode (1,1,0) matches the analytical formula', () {
    final modes = calculateRoomModes(room, maxFrequencyHz: 300);
    // f(1,1,0) = (343/2)·√(1/25 + 1/16) ≈ 54.94 Hz
    expect(modeOf(modes, 1, 1, 0).frequency, closeTo(54.94, 0.05));
  });

  test('mode types are classified by number of non-zero indices', () {
    final modes = calculateRoomModes(room, maxFrequencyHz: 300);
    expect(modeOf(modes, 1, 0, 0).type, ModeType.axial);
    expect(modeOf(modes, 1, 1, 0).type, ModeType.tangential);
    expect(modeOf(modes, 1, 1, 1).type, ModeType.oblique);
  });

  test('strength weighting is 4 : 2 : 1 for axial : tangential : oblique', () {
    expect(ModeType.axial.strength, 4.0);
    expect(ModeType.tangential.strength, 2.0);
    expect(ModeType.oblique.strength, 1.0);
  });

  test('(0,0,0) is excluded and all modes are within the cutoff', () {
    final modes = calculateRoomModes(room, maxFrequencyHz: 100);
    expect(modes.any((m) => m.p == 0 && m.q == 0 && m.r == 0), isFalse);
    expect(modes.every((m) => m.frequency <= 100), isTrue);
  });

  test('modes are sorted by ascending frequency', () {
    final modes = calculateRoomModes(room, maxFrequencyHz: 300);
    for (var i = 1; i < modes.length; i++) {
      expect(modes[i].frequency, greaterThanOrEqualTo(modes[i - 1].frequency));
    }
  });

  test('the lowest mode of this room is the length axial mode', () {
    final modes = calculateRoomModes(room, maxFrequencyHz: 300);
    expect(modes.first.p, 1);
    expect(modes.first.q, 0);
    expect(modes.first.r, 0);
  });
}
