import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustics/note_mapping.dart';
import '../../state/room_providers.dart';
import '../mode_colors.dart';

/// A scrollable table of every calculated mode: frequency, indices (p,q,r),
/// type and nearest musical note. Tapping a row selects that mode for the
/// pressure map. This is the data backbone behind the visuals.
///
/// Returns slivers (a header + a lazily-built [SliverList]) so it must live
/// inside a [CustomScrollView]. Building rows on demand keeps editing the room
/// dimensions smooth even when there are hundreds of modes.
class ModeListSliver extends ConsumerWidget {
  const ModeListSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(modesProvider);
    final selected = ref.watch(selectedModeIndexProvider);

    if (modes.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No modes in range')),
        ),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  '${modes.length} modes',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const _HeaderRow(),
            ],
          ),
        ),
        SliverList.builder(
          itemCount: modes.length,
          itemBuilder: (context, i) {
            final mode = modes[i];
            final note = noteFromFrequency(mode.frequency);
            return InkWell(
              onTap: () =>
                  ref.read(selectedModeIndexProvider.notifier).state = i,
              child: Container(
                color: i == selected
                    ? Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.2)
                    : null,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    _cell('${mode.frequency.toStringAsFixed(1)} Hz', flex: 3),
                    _cell('(${mode.p},${mode.q},${mode.r})', flex: 3),
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colorForModeType(mode.type),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(mode.type.label),
                        ],
                      ),
                    ),
                    _cell(note.name, flex: 2),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _cell(String text, {int flex = 1}) =>
      Expanded(flex: flex, child: Text(text));
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelMedium
        ?.copyWith(fontWeight: FontWeight.bold);
    Widget h(String t, int flex) =>
        Expanded(flex: flex, child: Text(t, style: style));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          h('Freq', 3),
          h('(p,q,r)', 3),
          h('Type', 3),
          h('Note', 2),
        ],
      ),
    );
  }
}
