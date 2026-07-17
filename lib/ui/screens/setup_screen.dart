import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustics/speed_of_sound.dart';
import '../../core/geometry/room_shape.dart';
import '../../state/custom_room_providers.dart';
import '../../state/navigation_providers.dart';
import '../../state/room_providers.dart';
import '../app_theme.dart';
import '../widgets/floor_plan_editor.dart';
import '../widgets/iso_room_preview.dart';
import '../widgets/segmented_toggle.dart';
import '../widgets/stepper_field.dart';
import 'floor_plan_expanded_screen.dart';
import 'onboarding_screen.dart';

/// Resolution slider values at or above this switch the native solver to a
/// finer FEM mesh level (see resolutionToFemParams in
/// native/src/api/room_mode_solver.cpp) that's noticeably slower on a
/// concave floor plan -- several seconds rather than well under one. Keep
/// this in sync with that function's own resolution-to-level mapping.
const int _slowResolutionThreshold = 22;

/// Describe the room, then move to the viewer to see its computed modes.
/// Mirrors the design mockup's Setup screen: a Box/Custom toggle over
/// either the analytical box inputs or the numerical floor-plan editor.
class SetupScreen extends ConsumerWidget {
  const SetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kind = ref.watch(roomKindProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: appBackgroundGradient),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Room Modes',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('SETUP',
                          style: monoStyle(
                              fontSize: 11, color: AppColors.textFaint)),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: 'How this app works',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.help_outline_rounded,
                            size: 19, color: AppColors.textFaint),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const OnboardingScreen()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Describe the room, then calculate its resonant modes.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              SegmentedToggle<RoomKind>(
                value: kind,
                options: const [
                  (RoomKind.cuboid, 'Box'),
                  (RoomKind.custom, 'Custom'),
                ],
                onChanged: (v) => ref.read(roomKindProvider.notifier).state = v,
              ),
              const SizedBox(height: 14),
              if (kind == RoomKind.cuboid)
                const _CuboidSetup()
              else
                const _CustomSetup(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CuboidSetup extends ConsumerWidget {
  const _CuboidSetup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(roomProvider);
    final notifier = ref.read(roomProvider.notifier);
    final modes = ref.watch(modesProvider);
    final speed = speedOfSound(temperatureC: room.temperatureC);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 190,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: IsoRoomPreview(
            length: room.length,
            width: room.width,
            height: room.height,
          ),
        ),
        const SizedBox(height: 9),
        Column(
          children: [
            StepperField(
              label: 'Length',
              value: room.length,
              min: 2,
              max: 20,
              step: 0.1,
              suffix: 'm',
              onChanged: (v) => notifier.state = room.copyWith(length: v),
            ),
            const SizedBox(height: 9),
            StepperField(
              label: 'Width',
              value: room.width,
              min: 2,
              max: 20,
              step: 0.1,
              suffix: 'm',
              onChanged: (v) => notifier.state = room.copyWith(width: v),
            ),
            const SizedBox(height: 9),
            StepperField(
              label: 'Height',
              value: room.height,
              min: 2,
              max: 8,
              step: 0.1,
              suffix: 'm',
              onChanged: (v) => notifier.state = room.copyWith(height: v),
            ),
          ],
        ),
        const SizedBox(height: 9),
        StepperField(
          label: 'Air temperature',
          trailing: Text('c=${speed.toStringAsFixed(1)} m/s',
              style: monoStyle(fontSize: 11, color: AppColors.textFaint)),
          value: room.temperatureC,
          min: -10,
          max: 40,
          step: 1,
          decimals: 0,
          suffix: '°C',
          onChanged: (v) =>
              notifier.state = room.copyWith(temperatureC: v),
        ),
        const SizedBox(height: 16),
        _CalculateButton(
          label: 'Calculate ${modes.length} modes',
          onPressed: () {
            ref.read(appScreenProvider.notifier).state = AppScreen.viewer;
          },
        ),
      ],
    );
  }
}

class _CustomSetup extends ConsumerWidget {
  const _CustomSetup();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(floorPlanProvider);
    final planNotifier = ref.read(floorPlanProvider.notifier);
    final shape =
        ExtrudedPolygonShape(floor: plan.vertices, height: plan.height);
    final speed = speedOfSound(temperatureC: plan.temperatureC);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const FloorPlanExpandedScreen(),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
            ),
            child: AspectRatio(
              aspectRatio: 1.25,
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: FloorPlanEditor(interactive: false),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_full,
                              size: 12, color: AppColors.textSecondary),
                          SizedBox(width: 4),
                          Text('Tap to edit',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Footprint ${shape.extentX.toStringAsFixed(1)} × '
          '${shape.extentY.toStringAsFixed(1)} m  •  '
          'floor ${shape.floorArea.toStringAsFixed(1)} m²',
          style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final preset in roomPresets) ...[
              Expanded(
                child: _PresetButton(
                  label: preset.name,
                  onTap: () => planNotifier.state = plan.copyWith(
                      vertices: centerInWorld(preset.vertices)),
                ),
              ),
              if (preset != roomPresets.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 10),
        StepperField(
          label: 'Ceiling height',
          value: plan.height,
          min: 2,
          max: 5,
          step: 0.1,
          suffix: 'm',
          onChanged: (v) => planNotifier.state = plan.copyWith(height: v),
        ),
        const SizedBox(height: 9),
        StepperField(
          label: 'Air temperature',
          trailing: Text('c=${speed.toStringAsFixed(1)} m/s',
              style: monoStyle(fontSize: 11, color: AppColors.textFaint)),
          value: plan.temperatureC,
          min: -10,
          max: 40,
          step: 1,
          decimals: 0,
          suffix: '°C',
          onChanged: (v) =>
              planNotifier.state = plan.copyWith(temperatureC: v),
        ),
        const SizedBox(height: 12),
        _QualitySlider(
          label: 'Mesh resolution',
          value: plan.resolution.toDouble(),
          min: 10,
          max: 32,
          divisions: 22,
          onChanged: (v) =>
              planNotifier.state = plan.copyWith(resolution: v.round()),
        ),
        _QualitySlider(
          label: 'Modes',
          value: plan.modeCount.toDouble(),
          min: 4,
          max: 100,
          divisions: 96,
          onChanged: (v) =>
              planNotifier.state = plan.copyWith(modeCount: v.round()),
        ),
        Text(
          'Higher resolution = a finer solve mesh: more accurate modes but '
          'slower to compute. The 3D view renders that same mesh directly.',
          style: const TextStyle(fontSize: 11, color: AppColors.textFaint, height: 1.4),
        ),
        if (plan.resolution >= _slowResolutionThreshold) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber,
                  size: 16, color: AppColors.axial),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'At this resolution, non-rectangular rooms can take '
                  'several seconds or more to compute.',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.axial, height: 1.4),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _CalculateButton(
          label: 'Compute modes',
          onPressed: () async {
            if (plan.resolution >= _slowResolutionThreshold) {
              final proceed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppColors.surfaceAlt,
                  title: const Text('This may take a while'),
                  content: const Text(
                    'At this resolution, non-rectangular rooms can take '
                    'several seconds or more to solve -- the app will be '
                    'busy until it finishes. Continue?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Compute'),
                    ),
                  ],
                ),
              );
              if (proceed != true) return;
            }
            ref.read(analysisRequestProvider.notifier).state = plan;
            ref.read(selectedCustomModeProvider.notifier).state = null;
            ref.read(appScreenProvider.notifier).state = AppScreen.viewer;
          },
        ),
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _QualitySlider extends StatelessWidget {
  const _QualitySlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary))),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(value.round().toString(),
              textAlign: TextAlign.end,
              style: monoStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _CalculateButton extends StatelessWidget {
  const _CalculateButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.32),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 16, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
