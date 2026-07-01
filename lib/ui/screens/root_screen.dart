import 'package:flutter/material.dart';

import 'custom_room_screen.dart';
import 'home_screen.dart';

/// Top-level shell that switches between the analytical **Cuboid** calculator
/// (Phase 1) and the numerical **Custom 3D** room workflow (Phase 2).
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  int _index = 0;

  static const _titles = ['Room Mode Calculator', 'Custom Room (3D)'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      body: IndexedStack(
        index: _index,
        children: const [
          _CuboidBody(),
          CustomRoomScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.crop_square),
            label: 'Cuboid',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_in_ar),
            label: 'Custom 3D',
          ),
        ],
      ),
    );
  }
}

/// The Phase 1 calculator body without its own Scaffold/AppBar (the root shell
/// provides those).
class _CuboidBody extends StatelessWidget {
  const _CuboidBody();

  @override
  Widget build(BuildContext context) => const HomeScreen(showScaffold: false);
}
