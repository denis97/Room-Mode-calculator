import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether this build/platform can serve ads at all: the Google Mobile Ads
/// SDK exists only on Android/iOS, and widget tests must never touch the
/// plugin channels. Overridden in tests that exercise the gating logic.
final adsSupportedProvider = Provider<bool>((ref) {
  if (kIsWeb) return false;
  final isMobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (!isMobile) return false;
  // `flutter test` sets FLUTTER_TEST; the fake platform there is Android,
  // so without this a test pumping the solve overlay would hit the plugin.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
  return true;
});

/// Whether the one-time "Pro" purchase (ad removal) is owned. Persisted
/// locally so the app doesn't flash ads before the store restores the
/// purchase; the Play Billing purchase stream is the source of truth and
/// re-writes this on every app start.
class ProUnlock extends StateNotifier<bool> {
  ProUnlock() : super(false) {
    ready = _load();
  }

  static const _prefsKey = 'pro_unlocked';

  /// Completes once the persisted value has been read (awaited by tests).
  late final Future<void> ready;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted && prefs.getBool(_prefsKey) == true) state = true;
    } catch (_) {
      // No prefs (fresh install edge cases): stay unlocked=false; the
      // billing purchase stream restores ownership anyway.
    }
  }

  Future<void> set(bool owned) async {
    state = owned;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, owned);
    } catch (_) {
      // In-memory state still applies for this session.
    }
  }
}

final proUnlockedProvider =
    StateNotifierProvider<ProUnlock, bool>((ref) => ProUnlock());

/// The single switch everything ad-related hangs off: supported platform
/// and not bought out.
final adsEnabledProvider = Provider<bool>((ref) {
  final supported = ref.watch(adsSupportedProvider);
  final pro = ref.watch(proUnlockedProvider);
  return supported && !pro;
});
