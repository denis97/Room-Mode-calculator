import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/dimension_inputs.dart';
import '../widgets/frequency_axis.dart';
import '../widgets/mode_list.dart';
import '../widgets/piano_keyboard.dart';
import '../widgets/pressure_map.dart';

/// The single-screen home of the cuboid calculator. It stacks the input card,
/// the frequency axis, the piano keyboard, the pressure map, and the full mode
/// list — all driven live from the room inputs.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Room Mode Calculator'),
      ),
      body: ListView(
        children: const [
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
          Divider(height: 1),
          ModeList(),
          SizedBox(height: 24),
        ],
      ),
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
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
