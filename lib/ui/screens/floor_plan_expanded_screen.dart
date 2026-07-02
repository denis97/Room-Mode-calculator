import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/floor_plan_editor.dart';

/// A full-screen version of the floor-plan editor, reached by tapping the
/// small preview on the setup screen. Same shared [floorPlanProvider] state,
/// just with much more room to draw precisely and two-finger pan/zoom.
class FloorPlanExpandedScreen extends StatelessWidget {
  const FloorPlanExpandedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: appBackgroundGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.arrow_back_ios_new,
                            size: 15, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Floor plan',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Padding(
                  padding: EdgeInsets.only(left: 48),
                  child: Text(
                    'Drag vertices • tap an edge to add • long-press to remove • '
                    'two fingers to pan/zoom',
                    style: TextStyle(fontSize: 12, color: AppColors.textFaint),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const FloorPlanEditor(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
