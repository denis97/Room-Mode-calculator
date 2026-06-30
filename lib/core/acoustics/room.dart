import '../constants.dart';

/// An immutable description of a rectangular (cuboid) room plus the ambient
/// conditions that affect its modal behaviour.
///
/// All dimensions are in metres, temperature in degrees Celsius, RT60 in
/// seconds. This is the single input to the calculation layer.
class Room {
  const Room({
    this.length = AcousticDefaults.defaultLength,
    this.width = AcousticDefaults.defaultWidth,
    this.height = AcousticDefaults.defaultHeight,
    this.temperatureC = AcousticDefaults.temperatureC,
    this.rt60Seconds = AcousticDefaults.rt60Seconds,
  });

  final double length;
  final double width;
  final double height;
  final double temperatureC;
  final double rt60Seconds;

  /// Room volume in cubic metres.
  double get volume => length * width * height;

  Room copyWith({
    double? length,
    double? width,
    double? height,
    double? temperatureC,
    double? rt60Seconds,
  }) {
    return Room(
      length: length ?? this.length,
      width: width ?? this.width,
      height: height ?? this.height,
      temperatureC: temperatureC ?? this.temperatureC,
      rt60Seconds: rt60Seconds ?? this.rt60Seconds,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Room &&
      other.length == length &&
      other.width == width &&
      other.height == height &&
      other.temperatureC == temperatureC &&
      other.rt60Seconds == rt60Seconds;

  @override
  int get hashCode =>
      Object.hash(length, width, height, temperatureC, rt60Seconds);

  @override
  String toString() =>
      'Room(${length}x${width}x$height m, $temperatureC°C, RT60=$rt60Seconds s)';
}
