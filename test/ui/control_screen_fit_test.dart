import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';

import 'support/app_fonts.dart';
import 'support/pump_control.dart';

/// The Control column fits the Galaxy S25 without scrolling (2.0.21).
/// Geometry from the device (`wm size` 1080 × 2340, `wm density` 480 →
/// 3.0; `dumpsys window`: status bar 103 px, navigation bar 45 px), the
/// bundled fonts loaded so text metrics are the device's — with the test
/// framework's placeholder font the same column measures 55 dp taller.
/// Before the rhythm trim this overshot by 18.3 dp (≈ 18 dp measured on
/// the phone); the trim takes out 30.
void main() {
  testWidgets('android: the Control column fits the S25 viewport with slack', (tester) async {
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
    // Not a hairline fit: at least 8 dp to spare for a taller status bar.
    // (The scroll viewport sizes itself to the content once nothing
    // overflows, so the available height comes from the view.)
    final view = tester.view;
    final available = (view.physicalSize.height - view.viewPadding.top - view.viewPadding.bottom) / view.devicePixelRatio;
    final column = tester.getSize(find.byKey(ControlKeys.column)).height;
    final used = column + 6 + 28; // Android content padding top/bottom
    expect(available - used, greaterThanOrEqualTo(8), reason: 'slack ${available - used} dp; available $available, column $column');
  });
}
