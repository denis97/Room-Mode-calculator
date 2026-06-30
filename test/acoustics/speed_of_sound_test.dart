import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/acoustics/speed_of_sound.dart';

void main() {
  test('speed of sound at 0 °C is the reference 331.3 m/s', () {
    expect(speedOfSound(temperatureC: 0), closeTo(331.3, 0.01));
  });

  test('speed of sound at 20 °C is ≈ 343.2 m/s', () {
    expect(speedOfSound(temperatureC: 20), closeTo(343.2, 0.2));
  });

  test('speed of sound increases with temperature', () {
    expect(speedOfSound(temperatureC: 30),
        greaterThan(speedOfSound(temperatureC: 10)));
  });
}
