import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/control_layout.dart';

import 'support/pump_control.dart';

Offset ringPoint(WidgetTester tester, double angleDeg) {
  final center = tester.getCenter(find.byKey(ControlKeys.dial));
  return center + Offset(math.cos(angleDeg * math.pi / 180), math.sin(angleDeg * math.pi / 180)) * 96;
}

void main() {
  testWidgets('compact = full width minus side padding; wider = interim centred column', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    expect(tester.getSize(find.byKey(ControlKeys.column)).width, 390 - 2 * 22);

    await resizeWindow(tester, tabletLandscape);
    final column = tester.getRect(find.byKey(ControlKeys.column));
    expect(column.width, kInterimColumnMaxWidth - 2 * 22);
    expect(column.center.dx, closeTo(1024 / 2, 0.5));

    await resizeWindow(tester, phoneLandscape);
    expect(tester.getSize(find.byKey(ControlKeys.column)).width, kInterimColumnMaxWidth - 2 * 22);
    expect(tester.takeException(), isNull, reason: 'compact height scrolls, never overflows');
  });

  testWidgets('an open sheet survives a width-class change', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    await tester.tap(find.byKey(ControlKeys.sourceTrigger));
    await tester.pumpAndSettle();
    expect(find.text('Select source'), findsOneWidget);

    await resizeWindow(tester, tabletLandscape);
    await tester.pump();
    expect(find.text('Select source'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an in-progress dial drag survives a width-class change', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    final gesture = await tester.startGesture(ringPoint(tester, -90));
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221237.5');

    await resizeWindow(tester, tabletLandscape);
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221237.5');
    expect(readState(tester).volumeDb, -25.0);

    await gesture.moveTo(ringPoint(tester, 0));
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), '\u221222.5');
    await gesture.up();
    await tester.pump();
    expect(readState(tester).volumeDb, -22.5);
  });

  testWidgets('a manual-IP draft survives a width-class change', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notConnected));
    await tester.tap(find.byKey(ControlKeys.deviceCard));
    await tester.pumpAndSettle();
    await tapRow(tester, 'Enter IP Manually');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText), '192.0.2.9');
    await tester.pump();

    await resizeWindow(tester, tabletLandscape);
    await tester.pump();
    expect(find.text('192.0.2.9'), findsOneWidget);
    expect(find.text('Enter IP Address'), findsOneWidget);
  });
}
