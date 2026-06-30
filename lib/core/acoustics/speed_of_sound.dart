import 'dart:math' as math;

import '../constants.dart';

/// Speed of sound in dry air as a function of temperature.
///
/// Uses the standard approximation `c = 331.3 · √(1 + T / 273.15)` m/s, where
/// `T` is the temperature in degrees Celsius. At 20 °C this yields ≈ 343.2 m/s.
double speedOfSound({double temperatureC = AcousticDefaults.temperatureC}) {
  return AcousticDefaults.speedOfSoundAtZeroC *
      math.sqrt(1 + temperatureC / 273.15);
}
