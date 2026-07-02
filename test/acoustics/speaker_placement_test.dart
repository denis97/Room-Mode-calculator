import 'package:flutter_test/flutter_test.dart';
import 'package:room_mode_calculator/core/acoustics/mode.dart';
import 'package:room_mode_calculator/core/acoustics/mode_calculator.dart';
import 'package:room_mode_calculator/core/acoustics/placement_advisor.dart';
import 'package:room_mode_calculator/core/acoustics/room.dart';
import 'package:room_mode_calculator/core/acoustics/room_response.dart';
import 'package:room_mode_calculator/core/acoustics/speaker_placement.dart';

void main() {
  const room = Room(length: 5, width: 4, height: 3);
  final modes = calculateRoomModes(room, maxFrequencyHz: 200);

  group('modeExcitations', () {
    test('corner placement maximally excites every mode', () {
      const corner = PlacementPoint(fx: 0, fy: 0, fz: 0);
      final exc = modeExcitations(modes, room, corner, corner);
      for (final e in exc) {
        expect(e.source, closeTo(1.0, 1e-9));
        expect(e.audibility, closeTo(1.0, 1e-9));
      }
    });

    test('speaker on the (1,0,0) nodal plane cannot excite it', () {
      const midLength = PlacementPoint(fx: 0.5, fy: 0.1, fz: 0.1);
      const corner = PlacementPoint(fx: 0, fy: 0, fz: 0);
      final exc = modeExcitations(modes, room, midLength, corner);
      final i100 =
          modes.indexWhere((m) => m.p == 1 && m.q == 0 && m.r == 0);
      expect(i100, greaterThanOrEqualTo(0));
      expect(exc[i100].source, closeTo(0, 1e-9));
      expect(exc[i100].audibility, closeTo(0, 1e-9));
      // But an even-order length mode (2,0,0) peaks there.
      final i200 =
          modes.indexWhere((m) => m.p == 2 && m.q == 0 && m.r == 0);
      expect(i200, greaterThanOrEqualTo(0));
      expect(exc[i200].source, closeTo(1.0, 1e-9));
    });

    test('audibility is the product of both endpoints', () {
      const speaker = PlacementPoint(fx: 0.2, fy: 0.3, fz: 0.4);
      const listener = PlacementPoint(fx: 0.6, fy: 0.7, fz: 0.5);
      final exc = modeExcitations(modes, room, speaker, listener);
      final excSwapped = modeExcitations(modes, room, listener, speaker);
      for (var i = 0; i < exc.length; i++) {
        expect(exc[i].audibility, closeTo(excSwapped[i].audibility, 1e-12));
      }
    });
  });

  group('computeRoomResponse', () {
    const corner = PlacementPoint(fx: 0.02, fy: 0.02, fz: 0.02);
    const seat = PlacementPoint(fx: 0.38, fy: 0.5, fz: 0.4);

    test('peaks at the first axial mode for corner-to-corner placement', () {
      const farCorner = PlacementPoint(fx: 0.98, fy: 0.98, fz: 0.98);
      final curve = computeRoomResponse(modes, room, corner, farCorner,
          maxHz: 200, points: 400);
      final f100 = modes
          .firstWhere((m) => m.p == 1 && m.q == 0 && m.r == 0)
          .frequency; // 34.3 Hz for c = 343 m/s

      // The level right at the mode should exceed the level a half-octave up
      // (between modes).
      double dbNear(double f) {
        var best = 0;
        var bestDist = double.infinity;
        for (var i = 0; i < curve.frequencies.length; i++) {
          final d = (curve.frequencies[i] - f).abs();
          if (d < bestDist) {
            bestDist = d;
            best = i;
          }
        }
        return curve.db[best];
      }

      expect(dbNear(f100), greaterThan(dbNear(f100 * 1.4)));
    });

    test('a mode neither endpoint couples to leaves no peak', () {
      // Both points on the (1,0,0) nodal plane: x = L/2.
      const src = PlacementPoint(fx: 0.5, fy: 0.15, fz: 0.15);
      const lis = PlacementPoint(fx: 0.5, fy: 0.8, fz: 0.5);
      final withNull =
          computeRoomResponse(modes, room, src, lis, maxHz: 200, points: 400);
      final reference =
          computeRoomResponse(modes, room, corner, seat, maxHz: 200, points: 400);

      final f100 = modes
          .firstWhere((m) => m.p == 1 && m.q == 0 && m.r == 0)
          .frequency;
      double slope(ResponseCurve c) {
        // Peakiness proxy: level at f100 minus level 10 Hz below.
        double at(double f) {
          var best = 0;
          var bestDist = double.infinity;
          for (var i = 0; i < c.frequencies.length; i++) {
            final d = (c.frequencies[i] - f).abs();
            if (d < bestDist) {
              bestDist = d;
              best = i;
            }
          }
          return c.db[best];
        }

        return at(f100) - at(f100 - 10);
      }

      expect(slope(reference), greaterThan(slope(withNull)));
    });

    test('response is reciprocal in speaker and listener', () {
      final a =
          computeRoomResponse(modes, room, corner, seat, maxHz: 200);
      final b =
          computeRoomResponse(modes, room, seat, corner, maxHz: 200);
      for (var i = 0; i < a.db.length; i++) {
        expect(a.db[i], closeTo(b.db[i], 1e-9));
      }
    });

    test('empty modes give an empty curve', () {
      final curve = computeRoomResponse(
          const <RoomMode>[], room, corner, seat,
          maxHz: 200);
      expect(curve.isEmpty, isTrue);
      expect(curve.flatness, 0);
    });
  });

  group('computeFlatnessGrid', () {
    test('produces a finite grid matching the room aspect', () {
      final grid = computeFlatnessGrid(AdvisorRequest(
        room: room,
        modes: modes,
        fixed: const PlacementPoint(fx: 0.38, fy: 0.5, fz: 0.4),
        movingHeightFraction: 0.15,
        maxHz: 200,
        cols: 15,
        freqPoints: 48,
      ));
      expect(grid.cols, 15);
      expect(grid.rows, 12); // 15 * 4/5
      expect(grid.values.length, grid.cols * grid.rows);
      expect(grid.min, lessThanOrEqualTo(grid.max));
      for (final v in grid.values) {
        expect(v.isFinite, isTrue);
        expect(v, greaterThanOrEqualTo(0));
      }
    });

    test('bestSpot returns the flattest cell', () {
      final grid = computeFlatnessGrid(AdvisorRequest(
        room: room,
        modes: modes,
        fixed: const PlacementPoint(fx: 0.38, fy: 0.5, fz: 0.4),
        movingHeightFraction: 0.15,
        maxHz: 200,
        cols: 10,
        freqPoints: 32,
      ));
      final best = bestSpot(grid, 0.15);
      final col = (best.fx * grid.cols - 0.5).round();
      final row = (best.fy * grid.rows - 0.5).round();
      expect(grid.valueAt(col, row), grid.min);
    });
  });
}
