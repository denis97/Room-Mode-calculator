import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/app_theme.dart';
import 'ui/screens/root_screen.dart';

void main() {
  runApp(const ProviderScope(child: RoomModeApp()));
}

class RoomModeApp extends StatelessWidget {
  const RoomModeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Room Mode Calculator',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootScreen(),
    );
  }
}
