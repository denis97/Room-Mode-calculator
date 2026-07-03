import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'monetization_providers.dart';

/// The one product: a non-consumable that permanently removes ads. Must
/// match the product ID configured in the Play Console.
const kProProductId = 'pro_no_ads';

/// What the Pro sheet needs to render: store availability, the localized
/// price, and purchase progress/errors.
class ProShopState {
  const ProShopState({
    this.available = false,
    this.price,
    this.purchasing = false,
    this.error,
  });

  final bool available;
  final String? price;
  final bool purchasing;
  final String? error;

  ProShopState copyWith({
    bool? available,
    String? price,
    bool? purchasing,
    String? error,
    bool clearError = false,
  }) {
    return ProShopState(
      available: available ?? this.available,
      price: price ?? this.price,
      purchasing: purchasing ?? this.purchasing,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Wraps Play Billing (via the in_app_purchase plugin): queries the Pro
/// product, listens to the purchase stream, and flips [proUnlockedProvider]
/// on purchase/restore. Constructed lazily the first time the Pro sheet
/// opens, so app startup never touches billing.
class ProShopController extends StateNotifier<ProShopState> {
  ProShopController(this._ref, {InAppPurchase? plugin})
      : _iap = plugin ?? InAppPurchase.instance,
        super(const ProShopState()) {
    _init();
  }

  final Ref _ref;
  final InAppPurchase _iap;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;

  Future<void> _init() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        if (mounted) {
          state = state.copyWith(
              available: false, error: 'Store not available on this device');
        }
        return;
      }
      _sub = _iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
        if (mounted) state = state.copyWith(error: '$e', purchasing: false);
      });
      final response = await _iap.queryProductDetails({kProProductId});
      if (!mounted) return;
      if (response.productDetails.isEmpty) {
        state = state.copyWith(
            available: false,
            error: 'Product not found — is $kProProductId configured?');
        return;
      }
      _product = response.productDetails.first;
      state = state.copyWith(
          available: true, price: _product!.price, clearError: true);
    } catch (e) {
      if (mounted) state = state.copyWith(available: false, error: '$e');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final owns = purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored;
      if (purchase.productID == kProProductId && owns) {
        await _ref.read(proUnlockedProvider.notifier).set(true);
        if (mounted) state = state.copyWith(purchasing: false);
      }
      if (purchase.status == PurchaseStatus.error) {
        if (mounted) {
          state = state.copyWith(
              purchasing: false, error: purchase.error?.message);
        }
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> buy() async {
    final product = _product;
    if (product == null || state.purchasing) return;
    state = state.copyWith(purchasing: true, clearError: true);
    try {
      await _iap.buyNonConsumable(
          purchaseParam: PurchaseParam(productDetails: product));
    } catch (e) {
      state = state.copyWith(purchasing: false, error: '$e');
    }
  }

  Future<void> restore() async {
    state = state.copyWith(clearError: true);
    try {
      await _iap.restorePurchases();
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final proShopProvider =
    StateNotifierProvider.autoDispose<ProShopController, ProShopState>(
  (ref) => ProShopController(ref),
);

/// Whether the platform even has a store to talk to (plugin is
/// Android/iOS/macOS; tests must not touch it).
bool get storeSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);
