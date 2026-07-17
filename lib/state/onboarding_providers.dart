import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _seenOnboardingKey = 'has_seen_onboarding';

/// Whether the first-launch onboarding intro has already been shown.
/// Overridden in `main()` with the value read from [SharedPreferences]
/// before the app's first frame, so the correct starting screen (onboarding
/// vs. straight to setup) is known synchronously -- no loading flash.
final hasSeenOnboardingProvider = StateProvider<bool>((ref) {
  throw UnimplementedError(
    'hasSeenOnboardingProvider must be overridden in main() with the '
    'value loaded from SharedPreferences before runApp().',
  );
});

/// Reads the persisted onboarding flag. Called once in `main()`.
Future<bool> loadHasSeenOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_seenOnboardingKey) ?? false;
}

/// Persists that onboarding has been shown (or re-shown and dismissed
/// again), so it doesn't reappear on the next launch.
Future<void> markOnboardingSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_seenOnboardingKey, true);
}
