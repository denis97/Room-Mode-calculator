import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/acoustics/placement_advisor.dart';
import '../../core/acoustics/room.dart';
import '../../core/acoustics/room_response.dart';
import '../../core/acoustics/speaker_placement.dart';
import '../../state/placement_providers.dart';
import '../../state/room_providers.dart';
import '../app_theme.dart';

const _speakerColor = AppColors.fieldPositive;
const _listenerColor = AppColors.accent;

/// Speaker-placement panel for the cuboid viewer: a top-down plan with
/// draggable speaker/listener markers (optionally over an advisor heatmap),
/// height sliders, and the predicted frequency response at the listener.
class PlacementPanel extends ConsumerWidget {
  const PlacementPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(roomProvider);
    final speakers = ref.watch(speakersProvider);
    final stereo = ref.watch(stereoPairProvider);
    final listener = ref.watch(listenerPosProvider);
    final response = ref.watch(roomResponseProvider);
    final advisorMode = ref.watch(advisorModeProvider);
    final advisorGrid = ref.watch(advisorGridProvider);
    final weightAxis = ref.watch(placementWeightAxisProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('SPEAKERS',
                style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: AppColors.textFaint)),
            const SizedBox(width: 10),
            _AdvisorChip(
              label: 'Stereo pair',
              selected: stereo,
              onTap: () =>
                  ref.read(stereoPairProvider.notifier).state = true,
            ),
            const SizedBox(width: 6),
            _AdvisorChip(
              label: 'Single sub',
              selected: !stereo,
              onTap: () =>
                  ref.read(stereoPairProvider.notifier).state = false,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _PlanView(
          room: room,
          speakers: speakers,
          listener: listener,
          grid: advisorMode == AdvisorMode.none
              ? null
              : advisorGrid.valueOrNull,
          mirrorBestSpot: stereo && advisorMode == AdvisorMode.speaker,
          onSpeakerMoved: (p) =>
              ref.read(speakerPosProvider.notifier).state = p,
          onListenerMoved: (p) =>
              ref.read(listenerPosProvider.notifier).state = p,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _LegendDot(
                color: _speakerColor,
                label: stereo ? 'speakers' : 'speaker'),
            const SizedBox(width: 12),
            const _LegendDot(color: _listenerColor, label: 'listener'),
            const Spacer(),
            if (advisorMode != AdvisorMode.none)
              advisorGrid.isLoading
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('cyan = flatter · ◎ best spot',
                      style:
                          TextStyle(fontSize: 10, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 10),
        _HeightSlider(
          label: 'Speaker height',
          color: _speakerColor,
          fraction: speakers.first.fz,
          room: room,
          onChanged: (fz) => ref.read(speakerPosProvider.notifier).state =
              ref.read(speakerPosProvider).copyWith(fz: fz),
        ),
        _HeightSlider(
          label: 'Ear height',
          color: _listenerColor,
          fraction: listener.fz,
          room: room,
          onChanged: (fz) => ref.read(listenerPosProvider.notifier).state =
              listener.copyWith(fz: fz),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('ADVISOR',
                style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: AppColors.textFaint)),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 6,
                children: [
                  for (final mode in AdvisorMode.values)
                    _AdvisorChip(
                      label: mode.label,
                      selected: advisorMode == mode,
                      onTap: () => ref
                          .read(advisorModeProvider.notifier)
                          .state = mode,
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => ref.read(placementWeightAxisProvider.notifier).state =
              !weightAxis,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Weight resonance axis by placement',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                Switch(
                  value: weightAxis,
                  onChanged: (v) => ref
                      .read(placementWeightAxisProvider.notifier)
                      .state = v,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('PREDICTED RESPONSE AT LISTENER',
                style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: AppColors.textFaint)),
            Text('σ ${response.flatness.toStringAsFixed(1)} dB',
                style: monoStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
        const SizedBox(height: 6),
        _ResponseCurveView(response: response),
        const SizedBox(height: 2),
        const Text(
          'Peaks can be EQ\'d down; nulls can\'t — move the speaker or '
          'the seat instead.',
          style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
        ),
      ],
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

class _AdvisorChip extends StatelessWidget {
  const _AdvisorChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.accent : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _HeightSlider extends StatelessWidget {
  const _HeightSlider({
    required this.label,
    required this.color,
    required this.fraction,
    required this.room,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final double fraction;
  final Room room;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11.5, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: color,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: fraction,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '${(fraction * room.height).toStringAsFixed(2)} m',
            textAlign: TextAlign.right,
            style: monoStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Top-down floor plan (x = length across, y = width down) with draggable
/// speaker/listener markers and an optional flatness heatmap underneath.
/// The first speaker is the primary; a second one is its stereo mirror and
/// drags in lockstep (moving either repositions the pair symmetrically).
class _PlanView extends StatefulWidget {
  const _PlanView({
    required this.room,
    required this.speakers,
    required this.listener,
    required this.grid,
    required this.mirrorBestSpot,
    required this.onSpeakerMoved,
    required this.onListenerMoved,
  });

  final Room room;
  final List<PlacementPoint> speakers;
  final PlacementPoint listener;
  final FlatnessGrid? grid;

  /// Whether the advisor's best-spot ring should show its stereo mirror too.
  final bool mirrorBestSpot;
  final ValueChanged<PlacementPoint> onSpeakerMoved;
  final ValueChanged<PlacementPoint> onListenerMoved;

  @override
  State<_PlanView> createState() => _PlanViewState();
}

enum _DragTarget { none, speaker, speakerMirror, listener }

class _PlanViewState extends State<_PlanView> {
  _DragTarget _dragging = _DragTarget.none;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height =
            (width * widget.room.width / widget.room.length).clamp(120.0, 300.0);
        final size = Size(width, height);

        Offset markerPx(PlacementPoint p) =>
            Offset(p.fx * size.width, p.fy * size.height);

        void moveTo(Offset local) {
          if (_dragging == _DragTarget.none) return;
          final p = PlacementPoint(
            fx: (local.dx / size.width).clamp(0.0, 1.0),
            fy: (local.dy / size.height).clamp(0.0, 1.0),
            fz: _dragging == _DragTarget.listener
                ? widget.listener.fz
                : widget.speakers.first.fz,
          );
          switch (_dragging) {
            case _DragTarget.speaker:
              widget.onSpeakerMoved(p);
            case _DragTarget.speakerMirror:
              // Dragging the right speaker repositions the pair via its
              // reflection, keeping the setup symmetric.
              widget.onSpeakerMoved(mirrorAcrossWidth(p));
            case _DragTarget.listener:
              widget.onListenerMoved(p);
            case _DragTarget.none:
              break;
          }
        }

        return GestureDetector(
          // Grab at pointer *down*: by pan-start the finger has already moved
          // past the touch slop, so a quick flick would miss the marker if
          // the grab radius were tested against the start position.
          onPanDown: (details) {
            final local = details.localPosition;
            const grabRadius = 32.0;
            var best = _DragTarget.none;
            var bestDist = grabRadius;
            void consider(_DragTarget target, PlacementPoint p) {
              final d = (local - markerPx(p)).distance;
              if (d < bestDist) {
                bestDist = d;
                best = target;
              }
            }

            consider(_DragTarget.speaker, widget.speakers.first);
            if (widget.speakers.length > 1) {
              consider(_DragTarget.speakerMirror, widget.speakers[1]);
            }
            consider(_DragTarget.listener, widget.listener);
            _dragging = best;
          },
          onPanStart: (details) => moveTo(details.localPosition),
          onPanUpdate: (details) => moveTo(details.localPosition),
          onPanEnd: (_) => _dragging = _DragTarget.none,
          onPanCancel: () => _dragging = _DragTarget.none,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CustomPaint(
              key: const Key('placement-plan'),
              size: size,
              painter: _PlanPainter(
                room: widget.room,
                speakers: widget.speakers,
                listener: widget.listener,
                grid: widget.grid,
                mirrorBestSpot: widget.mirrorBestSpot,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PlanPainter extends CustomPainter {
  _PlanPainter({
    required this.room,
    required this.speakers,
    required this.listener,
    required this.grid,
    required this.mirrorBestSpot,
  });

  final Room room;
  final List<PlacementPoint> speakers;
  final PlacementPoint listener;
  final FlatnessGrid? grid;
  final bool mirrorBestSpot;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF10131A),
    );

    final g = grid;
    if (g != null) {
      final cellW = size.width / g.cols;
      final cellH = size.height / g.rows;
      for (var row = 0; row < g.rows; row++) {
        for (var col = 0; col < g.cols; col++) {
          final t = g.normalizedAt(col, row);
          final color = Color.lerp(
            AppColors.fieldNegative,
            AppColors.fieldPositive,
            t,
          )!
              .withValues(alpha: 0.30);
          canvas.drawRect(
            Rect.fromLTWH(col * cellW, row * cellH, cellW + 0.5, cellH + 0.5),
            Paint()..color = color,
          );
        }
      }
      // Ring the flattest spot (and, for a stereo sweep, its mirror — the
      // sweep placed the pair symmetrically, so the best spot comes in twos).
      final best = bestSpot(g, 0);
      _bestRing(canvas, size, best, 0.85);
      if (mirrorBestSpot) {
        _bestRing(canvas, size, mirrorAcrossWidth(best), 0.45);
      }
    }

    // 1 m grid lines.
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var x = 1.0; x < room.length; x += 1.0) {
      final px = x / room.length * size.width;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), gridPaint);
    }
    for (var y = 1.0; y < room.width; y += 1.0) {
      final py = y / room.width * size.height;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), gridPaint);
    }

    canvas.drawRect(
      (Offset.zero & size).deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.18),
    );

    final stereo = speakers.length > 1;
    for (var i = 0; i < speakers.length; i++) {
      _marker(
        canvas,
        Offset(speakers[i].fx * size.width, speakers[i].fy * size.height),
        _speakerColor,
        stereo ? (i == 0 ? 'L' : 'R') : 'S',
      );
    }
    _listenerMarker(
      canvas,
      Offset(listener.fx * size.width, listener.fy * size.height),
    );
  }

  void _bestRing(Canvas canvas, Size size, PlacementPoint p, double alpha) {
    final at = Offset(p.fx * size.width, p.fy * size.height);
    canvas.drawCircle(
      at,
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: alpha),
    );
    canvas.drawCircle(
        at, 2, Paint()..color = Colors.white.withValues(alpha: alpha * 0.8));
  }

  /// The listener is drawn as a ring with a center dot (a "head from above")
  /// so it can't be confused with the lettered speaker markers.
  void _listenerMarker(Canvas canvas, Offset at) {
    canvas.drawCircle(
      at,
      13,
      Paint()..color = _listenerColor.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      at,
      8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = _listenerColor,
    );
    canvas.drawCircle(at, 3, Paint()..color = _listenerColor);
  }

  void _marker(Canvas canvas, Offset at, Color color, String label) {
    canvas.drawCircle(
      at,
      13,
      Paint()..color = color.withValues(alpha: 0.22),
    );
    canvas.drawCircle(at, 8.5, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0A0B0E),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_PlanPainter old) =>
      old.room != room ||
      !listEquals(old.speakers, speakers) ||
      old.listener != listener ||
      old.grid != grid ||
      old.mirrorBestSpot != mirrorBestSpot;
}

class _ResponseCurveView extends ConsumerWidget {
  const _ResponseCurveView({required this.response});

  final ResponseCurve response;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modes = ref.watch(modesProvider);
    final selected = ref.watch(selectedModeIndexProvider);
    final selectedFreq = (selected != null && selected < modes.length)
        ? modes[selected].frequency
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, 150),
          painter: _ResponsePainter(
            response: response,
            selectedFreq: selectedFreq,
          ),
        );
      },
    );
  }
}

class _ResponsePainter extends CustomPainter {
  _ResponsePainter({required this.response, required this.selectedFreq});

  final ResponseCurve response;
  final double? selectedFreq;

  @override
  void paint(Canvas canvas, Size size) {
    final r = response;
    if (r.isEmpty) {
      _text(
        canvas,
        'No modes to sum',
        Offset(size.width / 2, size.height / 2 - 6),
        const TextStyle(fontSize: 11, color: AppColors.textMuted),
        center: true,
      );
      return;
    }

    const padBottom = 16.0;
    final plotH = size.height - padBottom;
    final fMin = r.frequencies.first;
    final fMax = r.frequencies.last;

    var dbMin = double.infinity, dbMax = -double.infinity;
    for (final v in r.db) {
      if (v < dbMin) dbMin = v;
      if (v > dbMax) dbMax = v;
    }
    // Round the range out to 6 dB steps with headroom.
    final lo = ((dbMin - 3) / 6).floor() * 6.0;
    final hi = ((dbMax + 3) / 6).ceil() * 6.0;

    double xFor(double f) => (f - fMin) / (fMax - fMin) * size.width;
    double yFor(double db) => (hi - db) / (hi - lo) * plotH;

    // dB gridlines.
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    final labelStyle = monoStyle(fontSize: 9, color: AppColors.textFaint);
    for (var db = lo; db <= hi; db += 6) {
      final y = yFor(db);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      if (db != lo) {
        _text(canvas, '${db >= 0 ? '+' : ''}${db.round()}', Offset(2, y + 1),
            labelStyle);
      }
    }

    // Frequency ticks.
    final tick = fMax <= 120 ? 20.0 : (fMax <= 320 ? 50.0 : 100.0);
    for (var f = (fMin / tick).ceil() * tick; f <= fMax; f += tick) {
      final x = xFor(f);
      canvas.drawLine(
          Offset(x, plotH), Offset(x, plotH + 3), gridPaint..strokeWidth = 1);
      _text(canvas, '${f.round()}', Offset(x, plotH + 4), labelStyle,
          center: true);
    }

    // Selected-mode marker.
    if (selectedFreq != null && selectedFreq! >= fMin && selectedFreq! <= fMax) {
      final x = xFor(selectedFreq!);
      final dash = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      for (var y = 0.0; y < plotH; y += 6) {
        canvas.drawLine(Offset(x, y), Offset(x, y + 3), dash);
      }
    }

    // The curve, with a soft fill underneath.
    final path = Path();
    final fill = Path();
    for (var i = 0; i < r.frequencies.length; i++) {
      final x = xFor(r.frequencies[i]);
      final y = yFor(r.db[i]).clamp(0.0, plotH);
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, plotH);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, plotH);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.accent.withValues(alpha: 0.22),
            AppColors.accent.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, plotH)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = AppColors.accent,
    );
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style,
      {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = center ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(_ResponsePainter old) =>
      old.response != response || old.selectedFreq != selectedFreq;
}
