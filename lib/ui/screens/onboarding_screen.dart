import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/onboarding_providers.dart';
import '../app_theme.dart';

/// First-launch intro: a short swipeable explainer for what room modes are
/// and how the app's core workflows (shape, explore, judge quality) work.
/// Shown once (see onboarding_providers.dart), and replayable from the
/// Setup screen's help button.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingPage(
      title: 'Every room rings',
      body:
          'Sound bouncing between parallel walls builds up into "room modes" '
          '— resonant frequencies where bass either piles up or disappears '
          'entirely, depending on where you stand.',
      painter: _StandingWavePainter(),
    ),
    _OnboardingPage(
      title: 'Any shape you like',
      body:
          'Start with a simple box, or draw an L-shape, alcove, or anything '
          'else. The same solver handles both — on-device, no internet '
          'needed.',
      painter: _RoomShapesPainter(),
    ),
    _OnboardingPage(
      title: 'See it, hear it',
      body:
          'Every mode shows up on the frequency axis. Tap one to hear its '
          'pitch on the keyboard and watch its pressure field ripple '
          'through the room in 3D.',
      painter: _FrequencyPianoPainter(),
    ),
    _OnboardingPage(
      title: 'Judge the room',
      body:
          'The Bonello and Schroeder readouts tell you at a glance whether '
          'your room\'s modes are well spaced out, or clustered in a way '
          'that will color the bass.',
      painter: _QualityGaugePainter(),
    ),
  ];

  Future<void> _finish() async {
    await markOnboardingSeen();
    ref.read(hasSeenOnboardingProvider.notifier).state = true;
    // When replayed from Setup (pushed on top of the already-running app,
    // where hasSeenOnboardingProvider is already true) the state flip above
    // is a no-op, so pop this route explicitly instead of relying on
    // MaterialApp swapping `home`.
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: appBackgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 12, 0),
                  child: TextButton(
                    onPressed: _finish,
                    child: Text('Skip',
                        style: TextStyle(color: AppColors.textMuted)),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final p in _pages) _OnboardingPageView(page: p),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _page ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? AppColors.accent
                                  : AppColors.control,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          if (isLast) {
                            _finish();
                          } else {
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                            );
                          }
                        },
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: Text(isLast ? 'Get started' : 'Next'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.title,
    required this.body,
    required this.painter,
  });

  final String title;
  final String body;
  final CustomPainter painter;
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    // A fixed-size illustration + centered Column can overflow on a short
    // viewport (a small/landscape device, a resized window, large system
    // font scaling) since nothing here scrolls on its own. LayoutBuilder +
    // a min-height ConstrainedBox inside a SingleChildScrollView keeps the
    // usual centered look when everything fits, and falls back to
    // scrolling instead of clipping content when it doesn't. Capping the
    // illustration to a fraction of the viewport (rather than sizing it
    // from width alone via a bare AspectRatio) also makes that overflow
    // far less likely to begin with.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 32,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.42,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1.4,
                      child: CustomPaint(
                          painter: page.painter, child: const SizedBox.expand()),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    page.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    page.body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A box with a standing wave's pressure envelope arcing between its walls,
/// colored by the diverging pressure-field palette used everywhere else in
/// the app.
class _StandingWavePainter extends CustomPainter {
  const _StandingWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.7, h = size.height * 0.5;
    final left = (size.width - w) / 2, top = (size.height - h) / 2;
    final rect = Rect.fromLTWH(left, top, w, h);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final midY = rect.center.dy;
    final amp = h * 0.32;
    final path = Path();
    const steps = 60;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final x = rect.left + t * w;
      final y = midY - amp * math.sin(t * math.pi);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    for (final t in [0.0, 1.0]) {
      final x = rect.left + t * w;
      canvas.drawCircle(Offset(x, midY), 4,
          Paint()..color = AppColors.fieldPositive);
    }
    canvas.drawCircle(Offset(rect.left + w / 2, midY - amp), 4,
        Paint()..color = AppColors.fieldNegative);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A plain rectangle beside an L-shape, both outlined the same way, to say
/// "same tool, any floor plan".
class _RoomShapesPainter extends CustomPainter {
  const _RoomShapesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = AppColors.accentSoft;

    final boxSize = math.min(size.width * 0.32, size.height * 0.55);
    final gap = size.width * 0.10;
    final totalW = boxSize * 2 + gap;
    final left0 = (size.width - totalW) / 2;
    final top = (size.height - boxSize) / 2;

    final rect = Rect.fromLTWH(left0, top, boxSize, boxSize);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)), fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(6)), stroke);

    final lx = left0 + boxSize + gap;
    final notch = boxSize * 0.45;
    final lPath = Path()
      ..moveTo(lx, top)
      ..lineTo(lx + boxSize, top)
      ..lineTo(lx + boxSize, top + boxSize)
      ..lineTo(lx + notch, top + boxSize)
      ..lineTo(lx + notch, top + notch)
      ..lineTo(lx, top + notch)
      ..close();
    canvas.drawPath(lPath, fill);
    canvas.drawPath(lPath, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A mini frequency axis with mode-type-colored markers above a row of
/// piano-key rectangles.
class _FrequencyPianoPainter extends CustomPainter {
  const _FrequencyPianoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final axisY = size.height * 0.42;
    final left = size.width * 0.12, right = size.width * 0.88;

    canvas.drawLine(Offset(left, axisY), Offset(right, axisY),
        Paint()..color = AppColors.border..strokeWidth = 1.4);

    final markers = [
      (0.10, AppColors.axial),
      (0.32, AppColors.tangential),
      (0.55, AppColors.oblique),
      (0.75, AppColors.axial),
    ];
    for (final (t, color) in markers) {
      final x = left + t * (right - left);
      canvas.drawLine(Offset(x, axisY - 10), Offset(x, axisY + 10),
          Paint()..color = color..strokeWidth = 2.6..strokeCap = StrokeCap.round);
      canvas.drawCircle(Offset(x, axisY - 10), 3, Paint()..color = color);
    }

    final keyTop = axisY + size.height * 0.18;
    final keyH = size.height * 0.26;
    const keyCount = 9;
    final keyW = (right - left) / keyCount;
    for (var i = 0; i < keyCount; i++) {
      final x = left + i * keyW;
      final rect = Rect.fromLTWH(x, keyTop, keyW - 2, keyH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = i == 3 ? AppColors.accentSoft : AppColors.surfaceAlt,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..color = AppColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// A small ascending bar chart (Bonello's "non-decreasing mode count per
/// band" idea) with a check mark, standing in for the room-quality readouts.
class _QualityGaugePainter extends CustomPainter {
  const _QualityGaugePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final heights = [0.3, 0.45, 0.55, 0.8, 0.95];
    final barW = size.width * 0.09;
    final gap = size.width * 0.04;
    final totalW = heights.length * barW + (heights.length - 1) * gap;
    var x = (size.width - totalW) / 2;
    final baseY = size.height * 0.72;
    final maxH = size.height * 0.5;

    for (var i = 0; i < heights.length; i++) {
      final h = maxH * heights[i];
      final rect = Rect.fromLTWH(x, baseY - h, barW, h);
      final color = Color.lerp(AppColors.oblique, AppColors.accent, i / (heights.length - 1))!;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = color.withValues(alpha: 0.85),
      );
      x += barW + gap;
    }

    canvas.drawLine(
      Offset(size.width * 0.15, baseY),
      Offset(size.width * 0.85, baseY),
      Paint()..color = AppColors.border..strokeWidth = 1.4,
    );

    // Checkmark badge, top-right of the chart.
    final badgeCenter = Offset(size.width * 0.82, size.height * 0.16);
    canvas.drawCircle(badgeCenter, 14, Paint()..color = AppColors.oblique.withValues(alpha: 0.18));
    final checkPaint = Paint()
      ..color = AppColors.oblique
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final check = Path()
      ..moveTo(badgeCenter.dx - 6, badgeCenter.dy)
      ..lineTo(badgeCenter.dx - 1.5, badgeCenter.dy + 5)
      ..lineTo(badgeCenter.dx + 6.5, badgeCenter.dy - 6);
    canvas.drawPath(check, checkPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
