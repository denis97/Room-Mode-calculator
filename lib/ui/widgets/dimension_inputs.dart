import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/room_providers.dart';

/// Editable controls for the room dimensions, temperature, RT60 and the modal
/// frequency cutoff. Editing any value updates [roomProvider] /
/// [maxFrequencyProvider], which recomputes the modes live.
class DimensionInputs extends ConsumerWidget {
  const DimensionInputs({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(roomProvider);
    final maxFreq = ref.watch(maxFrequencyProvider);

    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Room', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                _NumberField(
                  label: 'Length (m)',
                  value: room.length,
                  onChanged: (v) => ref.read(roomProvider.notifier).state =
                      room.copyWith(length: v),
                ),
                const SizedBox(width: 8),
                _NumberField(
                  label: 'Width (m)',
                  value: room.width,
                  onChanged: (v) => ref.read(roomProvider.notifier).state =
                      room.copyWith(width: v),
                ),
                const SizedBox(width: 8),
                _NumberField(
                  label: 'Height (m)',
                  value: room.height,
                  onChanged: (v) => ref.read(roomProvider.notifier).state =
                      room.copyWith(height: v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _NumberField(
                  label: 'Temp (°C)',
                  value: room.temperatureC,
                  onChanged: (v) => ref.read(roomProvider.notifier).state =
                      room.copyWith(temperatureC: v),
                ),
                const SizedBox(width: 8),
                _NumberField(
                  label: 'RT60 (s)',
                  value: room.rt60Seconds,
                  onChanged: (v) => ref.read(roomProvider.notifier).state =
                      room.copyWith(rt60Seconds: v),
                ),
                const SizedBox(width: 8),
                _NumberField(
                  label: 'Max f (Hz)',
                  value: maxFreq,
                  onChanged: (v) =>
                      ref.read(maxFrequencyProvider.notifier).state = v,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    // Keep in sync if the value changed elsewhere, but don't fight the user
    // while they're typing the same number.
    final parsed = double.tryParse(_controller.text);
    if (parsed != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  String _format(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextField(
        controller: _controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (text) {
          // Keep typing instant (local controller), but defer the expensive
          // recompute until the user pauses, so the UI never recomputes
          // mid-keystroke.
          final v = double.tryParse(text);
          if (v == null || v <= 0) return;
          _debounce?.cancel();
          _debounce = Timer(
            const Duration(milliseconds: 300),
            () => widget.onChanged(v),
          );
        },
      ),
    );
  }
}
