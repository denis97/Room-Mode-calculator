/// App-wide default values and physical constants for the room mode
/// calculator. Keeping these in one place makes the calculation layer easy to
/// reason about and reuse in the future FEM phase.
library;

class AcousticDefaults {
  AcousticDefaults._();

  /// Default air temperature in degrees Celsius (room temperature).
  static const double temperatureC = 20.0;

  /// Reference speed of sound at 0 °C in m/s, used by [speedOfSound].
  static const double speedOfSoundAtZeroC = 331.3;

  /// Default highest modal frequency to enumerate, in Hz. Room modes matter
  /// most in the low-frequency range, so ~300 Hz is plenty for the cuboid view.
  static const double maxFrequencyHz = 300.0;

  /// Default listener ear height (for the horizontal pressure slice), in metres.
  static const double earHeightM = 1.2;

  /// Default reverberation time (RT60) in seconds, used for the Schroeder
  /// frequency when the user has not measured their own.
  static const double rt60Seconds = 0.4;

  /// Sensible default room dimensions in metres (length, width, height).
  static const double defaultLength = 5.0;
  static const double defaultWidth = 4.0;
  static const double defaultHeight = 3.0;
}
