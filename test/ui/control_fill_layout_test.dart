import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/control_layout.dart';
import 'package:devialet_expert_remote_app/ui/control/volume_dial.dart';

import 'support/fill_layout.dart';
import 'support/pump_control.dart';

/// `FilledControlLayout` at the edges of its rule (alternate v47c).
///
/// Red proofs (run once, 2026-09-26): a clamp floor of 180 in
/// `dialSizeFor` fails the short-screen case; a plain box in place of the
/// `SingleChildScrollView` overflows it; a fixed `scale: 1` readout fails
/// the type-scale case.
void main() {
  testWidgets('short screen: the dial stays at 220, the gap at its 8 dp minimum, and the column scrolls', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), size: const Size(360, 600));
    expect(tester.takeException(), isNull);
    final m = FillMeasurement(tester);
    expect(m.dial.width, kControlDialBase);
    expect(m.gap, closeTo(kControlFillMinGap, 0.01));
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.maxScrollExtent, greaterThan(0), reason: 'natural ${m.natural} dp in a ${600 - 6 - 28} dp viewport');
    expect(m.column.height, closeTo(m.natural, 0.01));
  });

  testWidgets('tall compact window: the dial grows by the rule and everything scales with k', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    final m = FillMeasurement(tester);
    expect(m.dial.width, closeTo(m.expectedDial, 0.01));
    expect(m.dial.width, greaterThan(kControlDialBase));
    expect(m.roundRow.top - m.dial.bottom, closeTo(kControlVolumeButtonsTop * m.k, 0.01));
    expect(m.sourceTrigger.bottom, closeTo(m.column.bottom, 0.01));
    final readout = tester.widget<DialReadout>(find.byType(DialReadout));
    expect(readout.scale, closeTo(m.k, 1e-9));
    expect(tester.widget<Text>(find.byKey(ControlKeys.dialValue)).style!.fontSize, closeTo(34 * m.k, 1e-6));
    expect(tester.widget<Text>(find.byKey(ControlKeys.dialUnit)).style!.fontSize, closeTo(12 * m.k, 1e-6));
    expect(tester.widget<Text>(find.byKey(ControlKeys.dialSourceLabel)).style!.fontSize, closeTo(10.5 * m.k, 1e-6));
    final dial = tester.widget<VolumeDial>(find.byType(VolumeDial));
    expect((dial.trackRadius, dial.trackWidth, dial.innerHitSlop), (96 * m.k, 10 * m.k, 28 * m.k));
  });

  testWidgets('tall wide window: the interim 480 column caps the dial at 300, never 0.88 × width', (tester) async {
    // Portrait tablet: enough spare that only the 300 cap limits the dial
    // (landscape at 768 dp tall is still spare-limited, ≈ 263).
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), size: const Size(768, 1024));
    final m = FillMeasurement(tester);
    expect(m.column.width, kInterimColumnMaxWidth - 2 * 22);
    expect(m.dial.width, closeTo(m.expectedDial, 0.01));
    expect(m.dial.width, kControlDialMax, reason: 'spare ${m.spare} allows more; the 300 cap wins');
    expect(m.dial.center.dx, closeTo(m.column.center.dx, 0.01));
  });

  testWidgets('the gap above Source never drops below 8 dp while the dial grows', (tester) async {
    for (final height in [640.0, 700.0, 780.0, 900.0]) {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), size: Size(360, height));
      final m = FillMeasurement(tester);
      expect(m.gap, greaterThanOrEqualTo(kControlFillMinGap - 0.001), reason: 'height $height: gap ${m.gap}');
      expect(tester.takeException(), isNull);
    }
  });
}
