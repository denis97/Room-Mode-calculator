import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/monetization/ads_service.dart';
import 'package:room_mode_calculator/monetization/monetization_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InterstitialGate', () {
    test('respects the minimum interval between ads', () {
      var now = DateTime(2026, 1, 1, 12, 0, 0);
      final gate = InterstitialGate(
        minInterval: const Duration(minutes: 3),
        maxPerSession: 10,
        clock: () => now,
      );

      expect(gate.allowed, isTrue);
      gate.recordShown();
      expect(gate.allowed, isFalse);

      now = now.add(const Duration(minutes: 2, seconds: 59));
      expect(gate.allowed, isFalse);

      now = now.add(const Duration(seconds: 2));
      expect(gate.allowed, isTrue);
    });

    test('caps the number of ads per session', () {
      var now = DateTime(2026, 1, 1);
      final gate = InterstitialGate(
        minInterval: Duration.zero,
        maxPerSession: 2,
        clock: () => now,
      );

      expect(gate.allowed, isTrue);
      gate.recordShown();
      now = now.add(const Duration(hours: 1));
      expect(gate.allowed, isTrue);
      gate.recordShown();
      now = now.add(const Duration(hours: 1));
      expect(gate.allowed, isFalse, reason: 'session cap reached');
    });
  });

  group('ad gating providers', () {
    test('ads are disabled under flutter test even on the fake platform',
        () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // The test env must never touch ad plugins.
      expect(container.read(adsSupportedProvider), isFalse);
      expect(container.read(adsEnabledProvider), isFalse);
      await container.read(proUnlockedProvider.notifier).ready;
    });

    test('Pro disables ads even where they are supported', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(overrides: [
        adsSupportedProvider.overrideWithValue(true),
      ]);
      addTearDown(container.dispose);

      expect(container.read(adsEnabledProvider), isTrue);
      await container.read(proUnlockedProvider.notifier).set(true);
      expect(container.read(adsEnabledProvider), isFalse);
    });

    test('Pro unlock persists across restarts', () async {
      SharedPreferences.setMockInitialValues({'pro_unlocked': true});
      final container = ProviderContainer(overrides: [
        adsSupportedProvider.overrideWithValue(true),
      ]);
      addTearDown(container.dispose);

      // The unlock loads asynchronously from prefs.
      await container.read(proUnlockedProvider.notifier).ready;
      expect(container.read(proUnlockedProvider), isTrue);
      expect(container.read(adsEnabledProvider), isFalse);
    });
  });
}
