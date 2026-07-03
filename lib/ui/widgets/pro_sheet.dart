import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../monetization/monetization_providers.dart';
import '../../monetization/purchase_service.dart';
import '../app_theme.dart';

/// Opens the "Remove ads" bottom sheet (the app's only purchase).
void showProSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => const _ProSheet(),
  );
}

class _ProSheet extends ConsumerWidget {
  const _ProSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pro = ref.watch(proUnlockedProvider);
    final shop = ref.watch(proShopProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.control,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Icon(Icons.workspace_premium_outlined,
                  color: AppColors.accent, size: 22),
              SizedBox(width: 8),
              Text('Remove ads',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            pro
                ? 'You own the ad-free upgrade — thanks for supporting the app!'
                : 'A one-time purchase removes every ad, forever. All '
                    'features stay free either way.',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 18),
          if (!pro) ...[
            FilledButton(
              onPressed: shop.available && !shop.purchasing
                  ? () => ref.read(proShopProvider.notifier).buy()
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: shop.purchasing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(shop.price == null
                        ? 'Remove ads'
                        : 'Remove ads · ${shop.price}'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(proShopProvider.notifier).restore(),
              child: const Text('Restore purchase',
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ),
          ],
          if (shop.error != null) ...[
            const SizedBox(height: 6),
            Text(shop.error!,
                style:
                    const TextStyle(fontSize: 11.5, color: AppColors.axial)),
          ],
        ],
      ),
    );
  }
}
