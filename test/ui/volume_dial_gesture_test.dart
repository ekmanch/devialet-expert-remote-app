import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';

import 'support/pump_control.dart';

/// A point on the ring track. The dial grows with the window (v47c), so
/// the track radius is 96 × (dial size / 220), not a constant; an explicit
/// [radius] is absolute (the centre dead zone).
Offset ringPoint(WidgetTester tester, double angleDeg, {double? radius}) {
  final center = tester.getCenter(find.byKey(ControlKeys.dial));
  final r = radius ?? tester.getSize(find.byKey(ControlKeys.dial)).width * 96 / 220;
  return center + Offset(math.cos(angleDeg * math.pi / 180), math.sin(angleDeg * math.pi / 180)) * r;
}

void main() {
  testWidgets('rotary drag: readout follows the finger, value commits on release', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    final gesture = await tester.startGesture(ringPoint(tester, 180)); // 9 o'clock
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221252.5');
    expect(readState(tester).volumeDb, -25.0, reason: 'not committed until release');

    await gesture.moveTo(ringPoint(tester, -90)); // 12 o'clock
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221237.5');

    await gesture.moveTo(ringPoint(tester, 0)); // 3 o'clock
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221222.5');

    await gesture.up();
    await tester.pump();
    expect(readState(tester).volumeDb, -22.5);
    expect(textAt(tester, ControlKeys.dialValue), '\u221222.5');
  });

  testWidgets('values are monotonic along the arc and quantized to 0.5 dB', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    final gesture = await tester.startGesture(ringPoint(tester, -225));
    final seen = <double>[];
    for (var a = -225.0; a <= 45; a += 10) {
      await gesture.moveTo(ringPoint(tester, a));
      await tester.pump();
      seen.add(double.parse(textAt(tester, ControlKeys.dialValue).replaceAll('\u2212', '-')));
    }
    await gesture.up();
    for (var i = 1; i < seen.length; i++) {
      expect(seen[i], greaterThanOrEqualTo(seen[i - 1]));
    }
    for (final v in seen) {
      expect((v * 2).roundToDouble(), v * 2);
    }
    expect(seen.first, -60.0);
    expect(seen.last, -15.0);
  });

  testWidgets('crossing the bottom dead zone never jumps between the ends', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    final gesture = await tester.startGesture(ringPoint(tester, 40)); // just before the end
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221216.0');
    await gesture.moveTo(ringPoint(tester, 90)); // straight down: dead zone
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221216.0');
    await gesture.up();
  });

  testWidgets('a press on the centre readout starts no drag', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(ControlKeys.dial)));
    await gesture.moveTo(ringPoint(tester, -90, radius: 20));
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221225.0');
    await gesture.up();
    await tester.pump();
    expect(readState(tester).volumeDb, -25.0);
  });

  testWidgets('disabled dial (Off) emits nothing', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.off));
    final gesture = await tester.startGesture(ringPoint(tester, 180));
    await gesture.moveTo(ringPoint(tester, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221225.0');
    expect(readState(tester).volumeDb, -25.0);
  });

  testWidgets('disabled mid-drag (amp went Off): the drag is dropped uncommitted; counter-half: kept On, release commits (3.6.4)', (
    tester,
  ) async {
    for (final goOff in [true, false]) {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      final gesture = await tester.startGesture(ringPoint(tester, 180));
      await tester.pump();
      expect(textAt(tester, ControlKeys.dialValue), '\u221252.5');
      if (goOff) {
        containerOf(tester)
            .read(ampStateProvider.notifier)
            .ingest(syntheticReport(ip: '192.0.2.22', name: 'My Devialet', isPoweredOn: false));
        await tester.pump();
        expect(textAt(tester, ControlKeys.dialValue), '\u221225.0', reason: 'the last known value, not the finger');
      }
      await gesture.up();
      await tester.pump();
      expect(readState(tester).volumeDb, goOff ? -25.0 : -52.5, reason: 'goOff=$goOff');
    }
  });

  testWidgets('muted: the readout follows the finger during a drag; the release unmutes (3.6.5)', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.muted));
    expect(textAt(tester, ControlKeys.dialValue), 'Muted');
    final gesture = await tester.startGesture(ringPoint(tester, 180));
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221252.5');
    expect(visibilityOf(tester, ControlKeys.dialUnit), isTrue);
    await gesture.up();
    await tester.pump();
    expect((readState(tester).volumeDb, readState(tester).isMuted), (-52.5, false));
    expect(textAt(tester, ControlKeys.dialValue), '\u221252.5');
  });

  testWidgets('the dial snaps to the configured step (a 2 dB grid here), not a constant', (tester) async {
    await pumpControl(tester, state: ControlViewState.connectedFixture.copyWith(stepDb: 2.0));
    final gesture = await tester.startGesture(ringPoint(tester, 180)); // 9 o'clock ≈ −52.5 on the 0.5 grid
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221252.0');
    await gesture.up();
  });

  testWidgets('the dial range comes from the state, not constants', (tester) async {
    final state = ControlViewState.connectedFixture.copyWith(floorDb: -50, ceilingDb: -20, volumeDb: -40);
    await pumpControl(tester, state: state);
    final gesture = await tester.startGesture(ringPoint(tester, -90)); // 12 o'clock = midpoint
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221235.0');
    await gesture.up();
  });
}
