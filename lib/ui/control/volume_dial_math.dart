import 'dart:math' as math;

import 'package:flutter/painting.dart' show Offset, Size;

/// Dial geometry ported from the Kotlin `VolumeDialView` via the v19
/// mockup (`START_ANGLE = -225`, `MAX_SWEEP = 270`): the arc starts at
/// 7:30, sweeps clockwise through 12 o'clock to 4:30, leaving a 90° gap
/// centred at the bottom. Angles use the canvas convention shared by
/// SVG and Flutter (0° = 3 o'clock, positive = clockwise).
const double kDialStartAngleDeg = -225;
const double kDialMaxSweepDeg = 270;

/// 0..1 position of [db] between [minDb] and [maxDb]; 0 when the range is
/// empty or inverted, so a bad setting never paints a lie.
double dialFraction(double db, double minDb, double maxDb) {
  if (maxDb <= minDb) return 0;
  return ((db - minDb) / (maxDb - minDb)).clamp(0.0, 1.0);
}

double dbForFraction(double fraction, double minDb, double maxDb) =>
    minDb + fraction.clamp(0.0, 1.0) * (maxDb - minDb);

/// Nearest multiple of [stepDb]; the readout shows half-dB steps while
/// dragging (the settings-driven step is Task 3.6.x).
double quantizeDb(double db, double stepDb) => (db / stepDb).round() * stepDb;

/// Pointer position → arc fraction. Inside the bottom 90° dead zone:
/// on a *start* ([snapInDeadZone] true) snap to the nearer end; on an
/// *update* return `null` so a finger crossing the bottom never jumps
/// between max and min.
double? dialFractionForPointer(Offset local, Size box, {required bool snapInDeadZone}) {
  final d = local - box.center(Offset.zero);
  final angleDeg = math.atan2(d.dy, d.dx) * 180 / math.pi;
  final rel = ((angleDeg - kDialStartAngleDeg) % 360 + 360) % 360;
  if (rel <= kDialMaxSweepDeg) return rel / kDialMaxSweepDeg;
  if (!snapInDeadZone) return null;
  final deadZoneMiddle = kDialMaxSweepDeg + (360 - kDialMaxSweepDeg) / 2;
  return rel < deadZoneMiddle ? 1.0 : 0.0;
}

/// The drag target is the ring band, wider than the painted track
/// (TODO 2.0.4): from [innerRadius] out to [outerRadius]. The centre
/// (readout) is not a drag target.
bool dialHitTest(Offset local, Size box, {required double innerRadius, required double outerRadius}) {
  final distance = (local - box.center(Offset.zero)).distance;
  return distance >= innerRadius && distance <= outerRadius;
}
