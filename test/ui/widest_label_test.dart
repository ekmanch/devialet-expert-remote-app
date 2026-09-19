import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/widgets/widest_label.dart';

import 'support/pump_control.dart';

void main() {
  testWidgets('WidestLabel is as wide as its widest candidate', (tester) async {
    const style = TextStyle(fontSize: 14);
    Widget build(String current) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: WidestLabel(candidates: const ['Mute', 'Unmute'], current: current, style: style)),
    );
    await tester.pumpWidget(build('Mute'));
    final narrow = tester.getSize(find.byType(WidestLabel));
    await tester.pumpWidget(build('Unmute'));
    final wide = tester.getSize(find.byType(WidestLabel));
    expect(narrow.width, wide.width);
    expect(narrow.width, tester.getSize(find.text('Unmute')).width);
  });

  testWidgets('mute icon does not move between Mute and Unmute (checklist 16)', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    final iconBefore = tester.getTopLeft(find.byKey(ControlKeys.muteIcon));
    final labelBefore = tester.getSize(find.ancestor(of: find.byKey(ControlKeys.muteLabel), matching: find.byType(WidestLabel)));
    await tester.tap(find.byKey(ControlKeys.muteButton));
    await tester.pump(const Duration(milliseconds: 200));
    expect(textAt(tester, ControlKeys.muteLabel), 'Unmute');
    expect(tester.getTopLeft(find.byKey(ControlKeys.muteIcon)), iconBefore);
    expect(tester.getSize(find.ancestor(of: find.byKey(ControlKeys.muteLabel), matching: find.byType(WidestLabel))), labelBefore);
  });

  testWidgets('power icon does not move across Power Off / Power On / Powering on…', (tester) async {
    final positions = <Offset>{};
    final widths = <double>{};
    for (final scenario in [DebugScenario.connected, DebugScenario.off, DebugScenario.booting]) {
      await pumpControl(tester, state: ControlViewState.forScenario(scenario));
      positions.add(tester.getTopLeft(find.byKey(ControlKeys.powerIcon)));
      widths.add(tester.getSize(find.ancestor(of: find.byKey(ControlKeys.powerLabel), matching: find.byType(WidestLabel))).width);
    }
    expect(positions, hasLength(1));
    expect(widths, hasLength(1));
  });
}
