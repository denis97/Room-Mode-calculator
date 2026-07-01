import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/dimension_inputs.dart';
import '../widgets/frequency_axis.dart';
import '../widgets/mode_3d_view.dart';
import '../widgets/mode_list.dart';
import '../widgets/piano_keyboard.dart';
import '../widgets/pressure_map.dart';
import '../widgets/room_quality_card.dart';

/// The single-screen home of the cuboid calculator. It stacks the input card,
/// the frequency axis, the piano keyboard, the pressure map, and the full mode
/// list — all driven live from the room inputs.
///
/// Built as a [CustomScrollView] so the (potentially long) mode list is a lazy
/// [SliverList] rather than an eagerly-built column.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, this.showScaffold = true});

  /// When false, returns just the scrollable body (the parent supplies the
  /// Scaffold/AppBar). Used by the root navigation shell.
  final bool showScaffold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const body = CustomScrollView(
      slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                DimensionInputs(),
                _SectionLabel('Frequency axis'),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: FrequencyAxis(),
                ),
                _SectionLabel('Keyboard — tap to hear a mode'),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: PianoKeyboard(),
                ),
                PressureMap(),
                Mode3DView(),
                RoomQualityCard(),
                Divider(height: 1),
              ],
            ),
          ),
          ModeListSliver(),
          SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      );

    if (!showScaffold) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Room Mode Calculator')),
      body: body,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }
}
