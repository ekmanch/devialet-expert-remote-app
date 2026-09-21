import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/volume_buttons.dart';

import 'support/pump_control.dart';

/// Task 3.5.1: the VOL −/+ buttons are inert by their own `enabled` flag,
/// with **no** `DimmedGroup` above them — the regression the audit found
/// (a re-parented button would have been live while Off). The `enabled:
/// true` half is the checklist-20 counter-test: the same tree, the same
/// tap, and the callback *does* fire, so the silence above is the gate's.
void main() {
  for (final variant in UiVariant.values) {
    testWidgets('disabled VOL buttons swallow taps by themselves (${variant.name})', (tester) async {
      var minus = 0;
      var plus = 0;
      await tester.pumpWidget(
        themed(
          VolumeButtons(enabled: false, onMinus: () => minus++, onPlus: () => plus++),
          variant: variant,
        ),
      );
      await tester.tap(find.byKey(ControlKeys.volMinus));
      await tester.tap(find.byKey(ControlKeys.volPlus));
      await tester.pump();
      expect((minus, plus), (0, 0));
    });

    testWidgets('counter-test: the same taps reach the callbacks when enabled (${variant.name})', (tester) async {
      var minus = 0;
      var plus = 0;
      await tester.pumpWidget(
        themed(
          VolumeButtons(enabled: true, onMinus: () => minus++, onPlus: () => plus++),
          variant: variant,
        ),
      );
      await tester.tap(find.byKey(ControlKeys.volMinus));
      await tester.tap(find.byKey(ControlKeys.volPlus));
      await tester.tap(find.byKey(ControlKeys.volPlus));
      await tester.pump();
      expect((minus, plus), (1, 2));
    });
  }
}
