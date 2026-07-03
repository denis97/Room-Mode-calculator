import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ad unit IDs. Defaults are Google's public *test* units, so every build
/// serves real-looking test ads until the production IDs are injected at
/// build time:
///
///   flutter build appbundle \
///     --dart-define=ADMOB_BANNER_UNIT=ca-app-pub-.../... \
///     --dart-define=ADMOB_INTERSTITIAL_UNIT=ca-app-pub-.../...
///
/// (The AdMob *application* ID is separate — a manifest placeholder, see
/// android/app/build.gradle.kts.)
class AdUnits {
  const AdUnits._();

  static const banner = String.fromEnvironment(
    'ADMOB_BANNER_UNIT',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const interstitial = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_UNIT',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );
}

/// Pure decision logic for when a full-screen ad is allowed: at most
/// [maxPerSession] per app session and never within [minInterval] of the
/// previous one. Kept plugin-free so it's unit-testable.
class InterstitialGate {
  InterstitialGate({
    this.minInterval = const Duration(minutes: 3),
    this.maxPerSession = 3,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final Duration minInterval;
  final int maxPerSession;
  final DateTime Function() _now;

  DateTime? _lastShown;
  int _shownThisSession = 0;

  bool get allowed {
    if (_shownThisSession >= maxPerSession) return false;
    final last = _lastShown;
    if (last != null && _now().difference(last) < minInterval) return false;
    return true;
  }

  void recordShown() {
    _lastShown = _now();
    _shownThisSession++;
  }
}

/// Thin lifecycle wrapper around the Google Mobile Ads SDK: one-time
/// consent-then-init, and a preloaded, frequency-capped interstitial.
/// All entry points are no-ops unless [enabled] was passed true, so callers
/// can invoke them unconditionally and let the provider decide.
class AdsService {
  AdsService({InterstitialGate? gate}) : gate = gate ?? InterstitialGate();

  final InterstitialGate gate;
  Future<void>? _initialization;
  InterstitialAd? _preloaded;
  bool _loading = false;

  /// GDPR/UMP consent gathering followed by SDK init. Idempotent; safe to
  /// call from several call sites (banner creation, interstitial hook).
  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Ask Google's User Messaging Platform whether a consent form is
      // required (EEA/UK) and show it if so. Errors (offline, misconfigured
      // AdMob account) must never block the app — ads just stay unfilled.
      final params = ConsentRequestParameters();
      await _gatherConsent(params);
    } catch (e) {
      debugPrint('UMP consent flow failed (continuing without): $e');
    }
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('Mobile Ads init failed: $e');
    }
  }

  Future<void> _gatherConsent(ConsentRequestParameters params) {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () async {
        try {
          if (await ConsentInformation.instance.isConsentFormAvailable()) {
            await _loadAndShowIfRequired();
          }
        } finally {
          if (!completer.isCompleted) completer.complete();
        }
      },
      (FormError error) {
        if (!completer.isCompleted) completer.complete();
      },
    );
    return completer.future;
  }

  Future<void> _loadAndShowIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// Preloads the next interstitial so showing it later is instant.
  Future<void> preloadInterstitial(bool enabled) async {
    if (!enabled || _preloaded != null || _loading) return;
    _loading = true;
    await ensureInitialized();
    await InterstitialAd.load(
      adUnitId: AdUnits.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _preloaded = ad;
          _loading = false;
        },
        onAdFailedToLoad: (error) {
          _loading = false;
        },
      ),
    );
  }

  /// Shows the preloaded interstitial if the frequency gate allows it.
  /// Fire-and-forget: returns immediately when disabled, unloaded or capped.
  void maybeShowInterstitial(bool enabled) {
    if (!enabled) return;
    final ad = _preloaded;
    if (ad == null) {
      // Nothing ready — warm one up for the next natural break instead.
      preloadInterstitial(enabled);
      return;
    }
    if (!gate.allowed) return;
    _preloaded = null;
    gate.recordShown();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preloadInterstitial(enabled);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
      },
    );
    ad.show();
  }
}

final adsServiceProvider = Provider<AdsService>((ref) => AdsService());
