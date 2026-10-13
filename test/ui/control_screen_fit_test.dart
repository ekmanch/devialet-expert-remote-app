import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/control_layout.dart';

import 'support/app_fonts.dart';
import 'support/fill_layout.dart';
import 'support/pump_control.dart';

/// The Control column on the Galaxy S25 (2.0.21 geometry: `wm size`
/// 1080 × 2340, `wm density` 480 → 3.0; `dumpsys window`: status bar
/// 103 px, navigation bar 45 px), the bundled fonts loaded so text
/// metrics are the device's — with the test framework's placeholder font
/// the same column measures 55 dp taller.
///
/// Alternate v47c "filled" layout: the column no longer leaves its spare
/// height under everything, so "≥ 8 dp of slack" is gone as a guard.
/// Instead: nothing scrolls, the column fills the viewport, Source is
/// pinned to its bottom, and the dial grew by the `fitDial()` rule
/// re-derived from measured parts — plus a tripwire band around the
/// measured S25 value, 262.7 dp with the bundled fonts (spare-limited, not width-capped: 0.88 × 316 =
/// 278 is the cap).
///
/// Red proofs (run once, 2026-09-26): `_dialSize = kControlDialBase`
/// hard-coded in `performLayout` fails the formula and the band; dropping
/// the screen's `ConstrainedBox(minHeight)` fails "fills the viewport".
void main() {
  testWidgets('android: the Control column fills the S25 viewport, no scroll; the dial grows into the spare height', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewPadding = const FakeViewPadding(top: 103, bottom: 45);
    tester.view.padding = const FakeViewPadding(top: 103, bottom: 45);
    addTearDown(tester.view.reset);
    await loadAppFonts();
    await tester.pumpWidget(hermeticApp());
    await tester.pump();

    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.maxScrollExtent, 0, reason: 'column ${tester.getSize(find.byKey(ControlKeys.column)).height} dp overshoots by ${position.maxScrollExtent} dp');

    final view = tester.view;
    final available = (view.physicalSize.height - view.viewPadding.top - view.viewPadding.bottom) / view.devicePixelRatio;
    final m = FillMeasurement(tester);
    expect(m.column.height, closeTo(available - 6 - 28, 0.01), reason: 'filled: the column is the viewport minus the Android content padding');
    expect(m.sourceTrigger.bottom, closeTo(m.column.bottom, 0.01), reason: 'Source is pinned to the bottom');
    expect(m.dial.width, closeTo(m.expectedDial, 0.01), reason: 'top ${m.top}, row ${m.roundRow.height}, bottom ${m.bottom}, spare ${m.spare}');
    expect(m.dial.width, greaterThan(kControlDialBase));
    expect(m.dial.width, lessThan(kControlDialWidthFraction * m.column.width), reason: 'spare-limited on the S25, not width-capped');
    // Tripwire: the measured S25 value; a rhythm change moves it.
    expect(m.dial.width, inInclusiveRange(258, 268), reason: 'measured ${m.dial.width}');
    expect(m.roundRow.top - m.dial.bottom, closeTo(kControlVolumeButtonsTop * m.k, 0.01), reason: 'the round row margin is 14·k');
    expect(m.gap, greaterThanOrEqualTo(kControlFillMinGap));
  });
}
