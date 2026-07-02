import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which room workflow is active: the analytical cuboid calculator or the
/// numerical custom-shape solver.
enum RoomKind { cuboid, custom }

/// The two top-level screens: describing the room, or viewing its computed
/// modes.
enum AppScreen { setup, viewer }

/// Which room workflow the user is currently working with. Shared by both
/// the setup and viewer screens so switching kinds doesn't lose either
/// room's state.
final roomKindProvider = StateProvider<RoomKind>((ref) => RoomKind.cuboid);

/// Which of the two top-level screens is showing.
final appScreenProvider = StateProvider<AppScreen>((ref) => AppScreen.setup);
