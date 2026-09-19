import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/control/volume_dial_math.dart';

void main() {
  const box = Size(220, 220);
  final center = box.center(Offset.zero);
  Offset at(double angleDeg, [double radius = 96]) =>
      center + Offset(math.cos(angleDeg * math.pi / 180), math.sin(angleDeg * math.pi / 180)) * radius;

  group('fraction ↔ dB', () {
    test('round-trips for the mockup range and for a settings-like range', () {
      for (final (min, max) in [(-60.0, -15.0), (-50.0, -20.0), (-96.0, 0.0)]) {
        for (var db = min; db <= max; db += 0.5) {
          expect(dbForFraction(dialFraction(db, min, max), min, max), closeTo(db, 1e-9));
        }
      }
    });

    test('mockup default: −25 in −60..−15 is 0.7778 (a 210° sweep)', () {
      expect(dialFraction(-25, -60, -15), closeTo(0.7778, 1e-4));
      expect(kDialMaxSweepDeg * dialFraction(-25, -60, -15), closeTo(210, 0.01));
    });

    test('clamps outside the range and never divides by an empty range', () {
      expect(dialFraction(-70, -60, -15), 0);
      expect(dialFraction(0, -60, -15), 1);
      expect(dialFraction(-25, -15, -60), 0, reason: 'inverted floor/ceiling paints nothing, not garbage');
      expect(dialFraction(-25, -25, -25), 0);
    });

    test('quantize to 0.5 dB', () {
      expect(quantizeDb(-25.24, 0.5), -25.0);
      expect(quantizeDb(-25.26, 0.5), -25.5);
      expect(quantizeDb(-25.75, 0.5), -26.0);
    });
  });

  group('pointer → fraction', () {
    test('start of the arc (7:30) is 0, end (4:30) is 1, 12 o\'clock is 0.5', () {
      expect(dialFractionForPointer(at(-225), box, snapInDeadZone: false), closeTo(0, 1e-9));
      expect(dialFractionForPointer(at(45), box, snapInDeadZone: false), closeTo(1, 1e-9));
      expect(dialFractionForPointer(at(-90), box, snapInDeadZone: false), closeTo(0.5, 1e-9));
      expect(dialFractionForPointer(at(180), box, snapInDeadZone: false), closeTo(45 / 270, 1e-9));
      expect(dialFractionForPointer(at(0), box, snapInDeadZone: false), closeTo(225 / 270, 1e-9));
    });

    test('bottom dead zone: null on update, nearest end on start', () {
      expect(dialFractionForPointer(at(90), box, snapInDeadZone: false), isNull);
      expect(dialFractionForPointer(at(60), box, snapInDeadZone: true), 1.0);
      expect(dialFractionForPointer(at(120), box, snapInDeadZone: true), 0.0);
    });

    test('radius does not matter, only the angle', () {
      expect(dialFractionForPointer(at(-90, 40), box, snapInDeadZone: false), closeTo(0.5, 1e-9));
    });
  });

  test('hit band: ring ± slop, not the centre, not outside the box', () {
    bool hit(Offset p) => dialHitTest(p, box, innerRadius: 63, outerRadius: 110);
    expect(hit(at(-90, 96)), isTrue);
    expect(hit(at(-90, 65)), isTrue);
    expect(hit(at(-90, 109)), isTrue);
    expect(hit(at(-90, 30)), isFalse);
    expect(hit(center), isFalse);
    expect(hit(at(-90, 120)), isFalse);
  });
}
