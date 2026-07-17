import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/onboarding_providers.dart';
import 'ui/app_theme.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/root_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hasSeenOnboarding = await loadHasSeenOnboarding();
  runApp(ProviderScope(
    overrides: [
      hasSeenOnboardingProvider.overrideWith((ref) => hasSeenOnboarding),
    ],
    child: const RoomModeApp(),
  ));
}

class RoomModeApp extends ConsumerWidget {
  const RoomModeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSeenOnboarding = ref.watch(hasSeenOnboardingProvider);
    return MaterialApp(
      title: 'Room Mode Calculator',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: hasSeenOnboarding ? const RootScreen() : const OnboardingScreen(),
    );
  }
}
