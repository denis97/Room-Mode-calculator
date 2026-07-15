import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/tone_player.dart';
import '../../core/acoustics/mode.dart';
import '../../monetization/solve_banner.dart';
import '../../core/acoustics/note_mapping.dart';
import '../../core/geometry/room_shape.dart' hide BoxShape;
import '../../core/numeric/modal_analysis.dart';
import '../../state/custom_room_providers.dart';
import '../../state/navigation_providers.dart';
import '../../state/room_providers.dart';
import '../app_theme.dart';
import '../mode_colors.dart';
import '../widgets/computed_mode_3d_view.dart';
import '../widgets/computed_mode_axis.dart';
import '../widgets/frequency_axis.dart';
import '../widgets/mode_3d_view.dart';
import '../widgets/piano_keyboard.dart';
import '../widgets/placement_panel.dart';
import '../widgets/pressure_map.dart';
import '../widgets/room_quality_card.dart';

/// Inspect the computed modes: frequency axis, a drag-to-orbit 3D pressure
/// field, mode-by-mode navigation, and the full table. Mirrors the design
/// mockup's Analyze screen for both the box and custom-shape workflows.
class ViewerScreen extends ConsumerStatefulWidget {
  const ViewerScreen({super.key});

  @override
  ConsumerState<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends ConsumerState<ViewerScreen> {
  final TonePlayer _player = TonePlayer();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = ref.watch(roomKindProvider);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: appBackgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              _ViewerHeader(kind: kind, player: _player),
              Expanded(
                child: kind == RoomKind.cuboid
                    ? _CuboidViewer(player: _player)
                    : _CustomViewer(player: _player),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Defaults the mode selection to the first mode the first time a screen
/// with results renders with nothing selected yet, so the mode-nav card and
/// the 3D view are never inconsistent (nav showing "1" while the 3D view
/// says nothing is selected). Deferred a frame since providers shouldn't be
/// written mid-build.
void _selectFirstModeNextFrame(WidgetRef ref, StateProvider<int?> provider) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (ref.read(provider) == null) ref.read(provider.notifier).state = 0;
  });
}

class _ViewerHeader extends ConsumerWidget {
  const _ViewerHeader({required this.kind, required this.player});

  final RoomKind kind;
  final TonePlayer player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String roomLabel;
    double? selectedFreq;

    if (kind == RoomKind.cuboid) {
      final room = ref.watch(roomProvider);
      final modes = ref.watch(modesProvider);
      final selected = ref.watch(selectedModeIndexProvider);
      roomLabel = '${room.length.toStringAsFixed(1)} × '
          '${room.width.toStringAsFixed(1)} × '
          '${room.height.toStringAsFixed(1)} m';
      if (selected != null && selected < modes.length) {
        selectedFreq = modes[selected].frequency;
      }
    } else {
      final plan = ref.watch(floorPlanProvider);
      final shape =
          ExtrudedPolygonShape(floor: plan.vertices, height: plan.height);
      roomLabel =
          'Custom · ${shape.floorArea.toStringAsFixed(0)} m²';
      final result = ref.watch(customModesProvider).valueOrNull;
      final selected = ref.watch(selectedCustomModeProvider);
      if (result != null && selected != null && selected < result.modes.length) {
        selectedFreq = result.modes[selected].frequency;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          _RoundIconButton(
            icon: Icons.arrow_back_ios_new,
            iconSize: 15,
            onTap: () =>
                ref.read(appScreenProvider.notifier).state = AppScreen.setup,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: InkWell(
              onTap: () =>
                  ref.read(appScreenProvider.notifier).state = AppScreen.setup,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            kind == RoomKind.cuboid
                                ? 'BOX ROOM'
                                : 'CUSTOM ROOM',
                            style: const TextStyle(
                              fontSize: 9,
                              letterSpacing: 0.5,
                              color: AppColors.textFaint,
                            ),
                          ),
                          Text(roomLabel,
                              style: monoStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const Text('Edit',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.accent,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          _RoundIconButton(
            icon: Icons.play_arrow_rounded,
            filled: true,
            onTap: selectedFreq == null
                ? null
                : () => player.playTone(selectedFreq!),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.iconSize = 18,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: filled ? AppColors.accentSoft : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon,
            size: iconSize,
            color: filled ? AppColors.accent : AppColors.textSecondary),
      ),
    );
  }
}

/// Shared chrome for a labeled section: an uppercase title row plus a
/// bordered panel, matching the mockup's card style.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.all(10),
  });

  final String title;
  final String? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textFaint,
                ),
              ),
              if (trailing != null)
                Text(trailing!,
                    style: monoStyle(fontSize: 11, color: AppColors.textFaint)),
            ],
          ),
        ),
        Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: child,
        ),
      ],
    );
  }
}

class _CuboidViewer extends ConsumerWidget {
  const _CuboidViewer({required this.player});

  final TonePlayer player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(modesProvider);
    final selected = ref.watch(selectedModeIndexProvider);
    final index = (selected != null && selected < modes.length) ? selected : null;
    final mode = index != null ? modes[index] : null;

    if (index == null && modes.isNotEmpty) {
      _selectFirstModeNextFrame(ref, selectedModeIndexProvider);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _Section(
          title: 'Resonances — tap a peak',
          trailing: '${modes.length} modes',
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Column(
            children: [
              const FrequencyAxis(),
              const SizedBox(height: 2),
              const Row(
                children: [
                  _LegendDot(color: AppColors.axial, label: 'axial'),
                  SizedBox(width: 12),
                  _LegendDot(color: AppColors.tangential, label: 'tangential'),
                  SizedBox(width: 12),
                  _LegendDot(color: AppColors.oblique, label: 'oblique'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: '3D pressure field',
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 260,
              child: Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF141A26), Color(0xFF0A0D13)],
                      ),
                    ),
                    child: SizedBox.expand(),
                  ),
                  const Mode3DView(),
                  if (mode != null)
                    _StageOverlays(
                      num: index! + 1,
                      freq: mode.frequency,
                      sub: '(${mode.p},${mode.q},${mode.r})',
                      tag: mode.type.label,
                      color: colorForModeType(mode.type),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ModeNav(
          index: index,
          count: modes.length,
          freqLabel: mode == null ? '—' : '${mode.frequency.toStringAsFixed(1)} Hz',
          noteLabel: mode == null ? '' : noteFromFrequency(mode.frequency).name,
          onIndexChanged: (i) =>
              ref.read(selectedModeIndexProvider.notifier).state = i,
        ),
        const SizedBox(height: 10),
        _AllModesButton(
          count: modes.length,
          onTap: () => _showCuboidModeSheet(context, ref, modes, selected),
        ),
        const SizedBox(height: 12),
        // Speaker placement: deferred to post-launch refinement
        // _DetailsExpander(
        //   title: 'Speaker placement',
        //   child: const PlacementPanel(),
        // ),
        _DetailsExpander(
          title: 'Keyboard — tap to hear a mode',
          child: const PianoKeyboard(),
        ),
        _DetailsExpander(
          title: 'Pressure slice',
          child: const PressureMap(),
        ),
        _DetailsExpander(
          title: 'Room quality',
          child: const RoomQualityCard(),
        ),
      ],
    );
  }

  void _showCuboidModeSheet(
    BuildContext context,
    WidgetRef ref,
    List<RoomMode> modes,
    int? selected,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ModeSheet(
        title: 'All modes',
        rows: [
          for (var i = 0; i < modes.length; i++)
            _ModeRow(
              num: i + 1,
              freqLabel: '${modes[i].frequency.toStringAsFixed(1)} Hz',
              subLabel: '(${modes[i].p},${modes[i].q},${modes[i].r})',
              tagLabel: modes[i].type.label,
              color: colorForModeType(modes[i].type),
              noteLabel: noteFromFrequency(modes[i].frequency).name,
              selected: i == selected,
              onTap: () {
                ref.read(selectedModeIndexProvider.notifier).state = i;
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _CustomViewer extends ConsumerWidget {
  const _CustomViewer({required this.player});

  final TonePlayer player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(customModesProvider);

    return resultAsync.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Solving the eigenproblem…',
                style: TextStyle(color: AppColors.textMuted)),
            // Fills the only genuinely dead wait in the app; renders
            // nothing at all for Pro users or while unfilled.
            SolveBanner(),
          ],
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Analysis failed: $e',
            style: const TextStyle(color: AppColors.axial)),
      ),
      data: (result) {
        if (result == null) {
          return const Center(
            child: Text('Press "Compute modes" to solve this room',
                style: TextStyle(color: AppColors.textMuted)),
          );
        }
        return _CustomViewerBody(result: result, player: player);
      },
    );
  }
}

class _CustomViewerBody extends ConsumerWidget {
  const _CustomViewerBody({required this.result, required this.player});

  final ModalAnalysisResult result;
  final TonePlayer player;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = result.modes;
    final selected = ref.watch(selectedCustomModeProvider);
    final index = (selected != null && selected < modes.length) ? selected : null;
    final mode = index != null ? modes[index] : null;

    if (index == null && modes.isNotEmpty) {
      _selectFirstModeNextFrame(ref, selectedCustomModeProvider);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        _Section(
          title: 'Resonances — tap a peak',
          trailing: '${modes.length} modes',
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: ComputedModeAxis(
            modes: modes,
            selectedIndex: index,
            onSelect: (i) => ref.read(selectedCustomModeProvider.notifier).state = i,
          ),
        ),
        const SizedBox(height: 12),
        _Section(
          title: '3D pressure field',
          trailing: '${result.mesh.triangleCount} faces',
          padding: EdgeInsets.zero,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 280,
              child: Stack(
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF141A26), Color(0xFF0A0D13)],
                      ),
                    ),
                    child: SizedBox.expand(),
                  ),
                  if (mode != null)
                    ComputedMode3DView(mesh: result.mesh, mode: mode)
                  else
                    const Center(
                      child: Text('Select a mode to view it in 3D',
                          style: TextStyle(color: AppColors.textMuted)),
                    ),
                  if (mode != null)
                    _StageOverlays(
                      num: index! + 1,
                      freq: mode.frequency,
                      sub: noteFromFrequency(mode.frequency).name,
                      tag: noteFromFrequency(mode.frequency).name,
                      color: AppColors.accent,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ModeNav(
          index: index,
          count: modes.length,
          freqLabel: mode == null ? '—' : '${mode.frequency.toStringAsFixed(1)} Hz',
          noteLabel: mode == null ? '' : noteFromFrequency(mode.frequency).name,
          onIndexChanged: (i) =>
              ref.read(selectedCustomModeProvider.notifier).state = i,
        ),
        const SizedBox(height: 10),
        _AllModesButton(
          count: modes.length,
          onTap: () => _showCustomModeSheet(context, ref, modes, selected),
        ),
      ],
    );
  }

  void _showCustomModeSheet(
    BuildContext context,
    WidgetRef ref,
    List<ComputedMode> modes,
    int? selected,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _ModeSheet(
        title: 'All modes',
        rows: [
          for (var i = 0; i < modes.length; i++)
            _ModeRow(
              num: i + 1,
              freqLabel: '${modes[i].frequency.toStringAsFixed(1)} Hz',
              subLabel: noteFromFrequency(modes[i].frequency).name,
              tagLabel: '',
              color: AppColors.accent,
              noteLabel: noteFromFrequency(modes[i].frequency).name,
              selected: i == selected,
              onTap: () {
                ref.read(selectedCustomModeProvider.notifier).state = i;
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
      ],
    );
  }
}

class _StageOverlays extends StatelessWidget {
  const _StageOverlays({
    required this.num,
    required this.freq,
    required this.sub,
    required this.tag,
    required this.color,
  });

  final int num;
  final double freq;
  final String sub;
  final String tag;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xB8060810),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Text('#$num',
                    style: monoStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                const SizedBox(width: 8),
                Container(width: 1, height: 22, color: Colors.white24),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${freq.toStringAsFixed(1)} Hz',
                        style: monoStyle(fontSize: 13, color: Colors.white)),
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (tag.isNotEmpty)
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x99060810),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(tag,
                      style: monoStyle(fontSize: 11, color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ModeNav extends StatelessWidget {
  const _ModeNav({
    required this.index,
    required this.count,
    required this.freqLabel,
    required this.noteLabel,
    required this.onIndexChanged,
  });

  final int? index;
  final int count;
  final String freqLabel;
  final String noteLabel;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    final i = index ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _NavArrow(
                icon: Icons.chevron_left,
                onTap: count == 0 ? null : () => onIndexChanged((i - 1).clamp(0, count - 1)),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text('MODE',
                        style: TextStyle(
                            fontSize: 9,
                            letterSpacing: 1,
                            color: AppColors.textFaint)),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: count == 0 ? '—' : '${i + 1}',
                            style: monoStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                          ),
                          TextSpan(
                            text: ' / $count',
                            style: monoStyle(
                                fontSize: 14, color: AppColors.textFaint),
                          ),
                        ],
                      ),
                    ),
                    Text('$freqLabel${noteLabel.isEmpty ? '' : ' · $noteLabel'}',
                        style: monoStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              _NavArrow(
                icon: Icons.chevron_right,
                onTap: count == 0 ? null : () => onIndexChanged((i + 1).clamp(0, count - 1)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: i.toDouble().clamp(0, (count - 1).clamp(0, 1 << 30).toDouble()),
              min: 0,
              max: (count - 1).clamp(0, 1 << 30).toDouble(),
              divisions: count > 1 ? count - 1 : null,
              onChanged: count == 0 ? null : (v) => onIndexChanged(v.round()),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.control,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: AppColors.textPrimary),
      ),
    );
  }
}

class _AllModesButton extends StatelessWidget {
  const _AllModesButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.menu, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 9),
                Text('All $count modes',
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ],
            ),
            const Icon(Icons.keyboard_arrow_up, size: 18, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

/// A collapsible section for the features the design mockup didn't design a
/// screen for (piano keyboard, pressure slice, room quality) — kept intact
/// and reskinned rather than dropped.
class _DetailsExpander extends StatefulWidget {
  const _DetailsExpander({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<_DetailsExpander> createState() => _DetailsExpanderState();
}

class _DetailsExpanderState extends State<_DetailsExpander> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _open = !_open),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(widget.title,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Icon(
                      _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
                  ],
                ),
              ),
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: widget.child,
              ),
          ],
        ),
      ),
    );
  }
}

class _ModeRow {
  const _ModeRow({
    required this.num,
    required this.freqLabel,
    required this.subLabel,
    required this.tagLabel,
    required this.color,
    required this.noteLabel,
    required this.selected,
    required this.onTap,
  });

  final int num;
  final String freqLabel;
  final String subLabel;
  final String tagLabel;
  final Color color;
  final String noteLabel;
  final bool selected;
  final VoidCallback onTap;
}

class _ModeSheet extends StatelessWidget {
  const _ModeSheet({required this.title, required this.rows});

  final String title;
  final List<_ModeRow> rows;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.74,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.control,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  Text('tap to view in 3-D',
                      style: monoStyle(fontSize: 11, color: AppColors.textFaint)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final row = rows[i];
                  return InkWell(
                    onTap: row.onTap,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      decoration: BoxDecoration(
                        color: row.selected ? AppColors.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text('${row.num}',
                                style: monoStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: row.selected
                                        ? AppColors.accent
                                        : AppColors.textFaint)),
                          ),
                          SizedBox(
                            width: 76,
                            child: Text(row.freqLabel,
                                style: monoStyle(fontSize: 13)),
                          ),
                          Expanded(
                            child: Text(row.subLabel,
                                style: monoStyle(
                                    fontSize: 12.5, color: AppColors.textSecondary)),
                          ),
                          if (row.tagLabel.isNotEmpty)
                            Row(
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                      color: row.color, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 6),
                                Text(row.tagLabel,
                                    style: const TextStyle(
                                        fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
