import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/navigation_providers.dart';
import 'setup_screen.dart';
import 'viewer_screen.dart';

/// Top-level shell: switches between describing the room ([SetupScreen]) and
/// inspecting its computed modes ([ViewerScreen]), for both the analytical
/// cuboid and the numerical custom-shape workflow.
class RootScreen extends ConsumerWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = ref.watch(appScreenProvider);
    return switch (screen) {
      AppScreen.setup => const SetupScreen(),
      AppScreen.viewer => const ViewerScreen(),
    };
  }
}
