import 'dart:ffi' as ffi;
import 'dart:io';

/// Raw `dart:ffi` mirror of `native/src/api/room_mode_solver.h`.
///
/// Field order here must exactly match the C struct. To make that safe
/// without depending on the C compiler's padding rules, the C struct groups
/// fields by size (pointers, then doubles, then int32s) so it has no interior
/// padding -- this Dart struct mirrors that same grouped order.
final class NativeSolveResult extends ffi.Struct {
  external ffi.Pointer<ffi.Int32> ci;
  external ffi.Pointer<ffi.Int32> cj;
  external ffi.Pointer<ffi.Int32> ck;
  external ffi.Pointer<ffi.Int32> neighbors;
  external ffi.Pointer<ffi.Double> frequencies;
  external ffi.Pointer<ffi.Double> fields;
  external ffi.Pointer<ffi.Char> errorMessage;

  @ffi.Double()
  external double h;
  @ffi.Double()
  external double originX;
  @ffi.Double()
  external double originY;
  @ffi.Double()
  external double originZ;

  @ffi.Int32()
  external int nx;
  @ffi.Int32()
  external int ny;
  @ffi.Int32()
  external int nz;
  @ffi.Int32()
  external int cellCount;
  @ffi.Int32()
  external int modeCount;
  @ffi.Int32()
  external int success;
}

typedef _SolveRoomModesNative = ffi.Pointer<NativeSolveResult> Function(
  ffi.Pointer<ffi.Double> polygonX,
  ffi.Pointer<ffi.Double> polygonY,
  ffi.Int32 polygonVertexCount,
  ffi.Double height,
  ffi.Double temperatureC,
  ffi.Int32 targetPerAxis,
  ffi.Int32 modeCount,
);
typedef SolveRoomModesDart = ffi.Pointer<NativeSolveResult> Function(
  ffi.Pointer<ffi.Double> polygonX,
  ffi.Pointer<ffi.Double> polygonY,
  int polygonVertexCount,
  double height,
  double temperatureC,
  int targetPerAxis,
  int modeCount,
);

typedef _FreeSolveResultNative = ffi.Void Function(ffi.Pointer<NativeSolveResult>);
typedef FreeSolveResultDart = void Function(ffi.Pointer<NativeSolveResult>);

/// Loads `libroom_mode_native` and resolves its two exported functions.
///
/// - Android: the shared library is bundled into the APK by Gradle's CMake
///   integration (see android/app/build.gradle) and resolved by name.
/// - iOS: statically linked into the app binary via the Runner Xcode project
///   (see native/README.md); `DynamicLibrary.process()` looks up symbols
///   already loaded into the running process rather than a separate .so/.dylib.
class RoomModeNativeLibrary {
  RoomModeNativeLibrary._(ffi.DynamicLibrary lib)
      : solveRoomModes = lib
            .lookup<ffi.NativeFunction<_SolveRoomModesNative>>('solve_room_modes')
            .asFunction(),
        freeSolveResult = lib
            .lookup<ffi.NativeFunction<_FreeSolveResultNative>>('free_solve_result')
            .asFunction();

  final SolveRoomModesDart solveRoomModes;
  final FreeSolveResultDart freeSolveResult;

  static RoomModeNativeLibrary? _instance;

  static RoomModeNativeLibrary get instance => _instance ??= RoomModeNativeLibrary._(_open());

  static ffi.DynamicLibrary _open() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libroom_mode_native.so');
    }
    if (Platform.isIOS) {
      return ffi.DynamicLibrary.process();
    }
    throw UnsupportedError(
      'The native room-mode solver is only wired up for Android and iOS.',
    );
  }
}
