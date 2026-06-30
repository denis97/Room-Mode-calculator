import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/acoustics/mode.dart';
import 'package:room_mode_calculator/core/acoustics/pressure_field.dart';
import 'package:room_mode_calculator/core/acoustics/room.dart';

void main() {
  const room = Room(length: 5, width: 4, height: 3);

  test('a (1,0,0) mode has antinodes at the end walls and a node at centre', () {
    const mode = RoomMode(p: 1, q: 0, r: 0, frequency: 34.3);
    // x = 0 wall: cos(0) = +1
    expect(pressureAt(mode, room, x: 0, y: 2, z: 1.5), closeTo(1.0, 1e-9));
    // x = L wall: cos(pi) = -1
    expect(pressureAt(mode, room, x: 5, y: 2, z: 1.5), closeTo(-1.0, 1e-9));
    // x = L/2: cos(pi/2) = 0  → nodal plane
    expect(pressureAt(mode, room, x: 2.5, y: 2, z: 1.5), closeTo(0.0, 1e-9));
  });

  test('sampled slice has the requested dimensions and bounded values', () {
    const mode = RoomMode(p: 2, q: 1, r: 0, frequency: 80);
    final grid = samplePressureSlice(mode, room, z: 1.2, cols: 32, rows: 16);
    expect(grid.cols, 32);
    expect(grid.rows, 16);
    expect(grid.values.length, 32 * 16);
    expect(grid.values.every((v) => v >= -1.0 && v <= 1.0), isTrue);
  });
}
