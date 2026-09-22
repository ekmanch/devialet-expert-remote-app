import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/control/device_card.dart';

import 'support/pump_control.dart';

/// Task 3.5.3 (owner report 2026-09-22): the booting dot pulsed at half the
/// KDE widget's speed. The widget's `AmpHeader.qml` runs 1 → 0.35 in
/// 550 ms and back in 550 ms; the mockup's `dotPulse 1.1s` is the same
/// full cycle. The controller's `duration` is one leg because
/// `repeat(reverse: true)` plays it both ways.
///
/// Counter-proof (checklist 20), run by hand with the old 1100 ms value:
/// the 550 ms sample reads ≈ 0.68 (halfway down the eased curve) and the
/// 1100 ms sample reads 0.35 — both assertions below fail.
void main() {
  double opacityAt(WidgetTester tester) => tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;

  testWidgets('booting dot: 1.0 → 0.35 in 550 ms, back to 1.0 at 1100 ms', (tester) async {
    await tester.pumpWidget(themed(const DeviceDot(state: DeviceDotState.booting)));
    expect(kDotPulseLeg, const Duration(milliseconds: 550));
    expect(opacityAt(tester), 1.0);
    await tester.pump(const Duration(milliseconds: 550));
    expect(opacityAt(tester), closeTo(0.35, 0.001));
    await tester.pump(const Duration(milliseconds: 550));
    expect(opacityAt(tester), closeTo(1.0, 0.001));
    await tester.pump(const Duration(milliseconds: 275));
    expect(opacityAt(tester), inExclusiveRange(0.35, 1.0), reason: 'still pulsing');
  });

  testWidgets('a non-booting dot does not animate', (tester) async {
    await tester.pumpWidget(themed(const DeviceDot(state: DeviceDotState.connected)));
    expect(find.byType(FadeTransition), findsNothing);
  });
}
