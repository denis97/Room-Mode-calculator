import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geometry/room_shape.dart';
import '../../core/numeric/modal_analysis.dart';
import '../../state/custom_room_providers.dart';
import '../widgets/computed_mode_3d_view.dart';
import '../widgets/custom_mode_slice_view.dart';
import '../widgets/floor_plan_editor.dart';

/// The non-rectangular room workflow: draw a floor plan, run the on-device
/// Phase 2 solver, and inspect the computed modes in 3D.
class CustomRoomScreen extends ConsumerWidget {
  const CustomRoomScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(floorPlanProvider);
    final planNotifier = ref.read(floorPlanProvider.notifier);
    final result = ref.watch(customModesProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Floor plan',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('Drag vertices • tap an edge to add • long-press to remove',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final preset in roomPresets)
                      OutlinedButton(
                        onPressed: () => planNotifier.state =
                            plan.copyWith(vertices: preset.vertices),
                        child: Text(preset.name),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const AspectRatio(
                  aspectRatio: 1,
                  child: FloorPlanEditor(),
                ),
                const SizedBox(height: 4),
                _FootprintReadout(plan: plan),
                _LabeledSlider(
                  label: 'Height',
                  value: plan.height,
                  min: 2,
                  max: 5,
                  suffix: 'm',
                  onChanged: (v) =>
                      planNotifier.state = plan.copyWith(height: v),
                ),
                _LabeledSlider(
                  label: 'Temperature',
                  value: plan.temperatureC,
                  min: 10,
                  max: 30,
                  suffix: '°C',
                  onChanged: (v) =>
                      planNotifier.state = plan.copyWith(temperatureC: v),
                ),
                _LabeledSlider(
                  label: 'Resolution',
                  value: plan.resolution.toDouble(),
                  min: 10,
                  max: 32,
                  divisions: 22,
                  suffix: 'cells',
                  onChanged: (v) => planNotifier.state =
                      plan.copyWith(resolution: v.round()),
                ),
                _ResolutionHint(plan: plan),
                _LabeledSlider(
                  label: 'Modes',
                  value: plan.modeCount.toDouble(),
                  min: 4,
                  max: 20,
                  divisions: 16,
                  suffix: '',
                  onChanged: (v) => planNotifier.state =
                      plan.copyWith(modeCount: v.round()),
                ),
                Text(
                  'Higher resolution = more accurate modes but slower '
                  '(work grows ~ resolution⁴). More modes cost more too, and '
                  'the highest ones need enough cells to be reliable.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.calculate),
                  label: const Text('Compute modes'),
                  onPressed: () {
                    ref.read(analysisRequestProvider.notifier).state = plan;
                    ref.read(selectedCustomModeProvider.notifier).state = null;
                  },
                ),
              ],
            ),
          ),
        ),
        result.when(
          loading: () => const Card(
            margin: EdgeInsets.all(12),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Solving the eigenproblem…'),
                  ],
                ),
              ),
            ),
          ),
          error: (e, _) => Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Analysis failed: $e'),
            ),
          ),
          data: (data) {
            if (data == null) {
              return const Card(
                margin: EdgeInsets.all(12),
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                    child: Text('Press "Compute modes" to solve this room'),
                  ),
                ),
              );
            }
            return _ResultsSection(result: data);
          },
        ),
      ],
    );
  }
}

class _ResultsSection extends ConsumerWidget {
  const _ResultsSection({required this.result});

  final ModalAnalysisResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedCustomModeProvider);
    final modes = result.modes;

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Computed modes (${result.grid.cellCount} cells)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < modes.length; i++)
                  ChoiceChip(
                    label: Text('${modes[i].frequency.toStringAsFixed(1)} Hz'),
                    selected: selected == i,
                    onSelected: (_) => ref
                        .read(selectedCustomModeProvider.notifier)
                        .state = i,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (selected != null && selected < modes.length) ...[
              AspectRatio(
                aspectRatio: 1.3,
                child: ComputedMode3DView(
                  grid: result.grid,
                  mode: modes[selected],
                ),
              ),
              const SizedBox(height: 12),
              Text('Interior slice',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              CustomModeSliceView(
                grid: result.grid,
                mode: modes[selected],
                maxHeight: result.grid.nz * result.grid.h,
              ),
            ] else
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: Text('Select a mode to view it in 3D')),
              ),
          ],
        ),
      ),
    );
  }
}

/// A compact readout of the room's real size, computed live from the plan.
class _FootprintReadout extends StatelessWidget {
  const _FootprintReadout({required this.plan});

  final FloorPlan plan;

  @override
  Widget build(BuildContext context) {
    final shape =
        ExtrudedPolygonShape(floor: plan.vertices, height: plan.height);
    final area = shape.floorArea;
    final volume = area * plan.height;
    return Row(
      children: [
        Icon(Icons.straighten,
            size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Footprint ${shape.extentX.toStringAsFixed(1)} × '
            '${shape.extentY.toStringAsFixed(1)} m  •  '
            'floor ${area.toStringAsFixed(1)} m²  •  '
            'volume ${volume.toStringAsFixed(1)} m³',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Live "what will the grid look like" hint: cell size and approximate grid
/// dimensions for the current resolution, so the accuracy/cost trade-off is
/// visible while dragging the slider.
class _ResolutionHint extends StatelessWidget {
  const _ResolutionHint({required this.plan});

  final FloorPlan plan;

  @override
  Widget build(BuildContext context) {
    final shape =
        ExtrudedPolygonShape(floor: plan.vertices, height: plan.height);
    final maxExtent =
        [shape.extentX, shape.extentY, plan.height].reduce(math.max);
    final h = maxExtent / plan.resolution;
    final nx = (shape.extentX / h).ceil();
    final ny = (shape.extentY / h).ceil();
    final nz = (plan.height / h).ceil();
    return Padding(
      padding: const EdgeInsets.only(left: 96, bottom: 4),
      child: Text(
        'cell ≈ ${(h * 100).toStringAsFixed(0)} cm • grid up to $nx×$ny×$nz',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.suffix,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final shown = divisions != null
        ? value.round().toString()
        : value.toStringAsFixed(1);
    return Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
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
          width: 64,
          child: Text('$shown $suffix', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
