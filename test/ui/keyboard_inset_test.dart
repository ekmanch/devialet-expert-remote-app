import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';

import 'support/pump_control.dart';

/// The Control scaffolds ignore the keyboard inset (`resizeToAvoidBottomInset:
/// false`): with the filled layout a shrinking body would re-fit the dial
/// behind the amp sheet's scrim while the manual-IP field is focused. The
/// sheet frame lifts its own panel, so the field must still clear the
/// keyboard (owner tweak, 2026-09-26).
///
/// Red proofs (run once, 2026-09-26): `resizeToAvoidBottomInset: true`
/// (the default) fails "the dial does not move"; a sheet frame without
/// its `viewInsets` reserve fails "the field clears the keyboard".
void main() {
  testWidgets('a keyboard under the manual-IP sheet lifts the field and leaves the dial alone', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notConnected));
    await openAmpSheet(tester);
    await tapRow(tester, 'Enter IP Manually');
    await tester.pumpAndSettle();
    final dialBefore = tester.getRect(find.byKey(ControlKeys.dial));

    const keyboard = 300.0; // dpr 1 in pumpControl: physical == logical
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    await tester.pumpAndSettle();

    final field = tester.getRect(find.byType(EditableText));
    expect(field.bottom, lessThanOrEqualTo(phonePortrait.height - keyboard), reason: 'field bottom ${field.bottom}');
    expect(tester.getRect(find.byKey(ControlKeys.dial)), dialBefore, reason: 'the Control column did not re-fit');
  });
}
