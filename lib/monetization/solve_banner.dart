import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../ui/app_theme.dart';
import 'ads_service.dart';
import 'monetization_providers.dart';

/// Banner ad shown inside the custom-room "Solving…" overlay — the one
/// place in the app with genuinely dead waiting time. Renders nothing when
/// ads are disabled (Pro, unsupported platform, tests) or while unfilled,
/// so the overlay never reserves empty space for it.
class SolveBanner extends ConsumerStatefulWidget {
  const SolveBanner({super.key});

  @override
  ConsumerState<SolveBanner> createState() => _SolveBannerState();
}

class _SolveBannerState extends ConsumerState<SolveBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Deferred: adsEnabled needs providers, not available in initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted || !ref.read(adsEnabledProvider)) return;
    await ref.read(adsServiceProvider).ensureInitialized();
    if (!mounted) return;
    final ad = BannerAd(
      adUnitId: AdUnits.banner,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: ad.size.width.toDouble(),
            height: ad.size.height.toDouble(),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: AdWidget(ad: ad),
          ),
          const SizedBox(height: 4),
          const Text('Ad',
              style: TextStyle(fontSize: 9, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}
