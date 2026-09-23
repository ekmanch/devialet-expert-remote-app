import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';

import 'support/pump_control.dart';

void main() {
  testWidgets('android: Material scaffold, bottom sheet, TextField, 26px title', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(CupertinoPageScaffold), findsNothing);
    expect(tester.widget<Text>(find.text('Expert Pro Remote')).style!.fontSize, 26);

    await tester.tap(find.byKey(ControlKeys.sourceTrigger));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await openAmpSheet(tester);
    await tapRow(tester, 'Enter IP Manually');
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(CupertinoTextField), findsNothing);
  });

  testWidgets('ios: Cupertino scaffold, frosted popup, CupertinoTextField, 30px title', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), variant: UiVariant.ios);
    expect(find.byType(CupertinoPageScaffold), findsOneWidget);
    expect(find.byType(Scaffold), findsNothing);
    expect(tester.widget<Text>(find.text('Expert Pro Remote')).style!.fontSize, 30);

    await tester.tap(find.byKey(ControlKeys.sourceTrigger));
    await tester.pumpAndSettle();
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await openAmpSheet(tester);
    await tapRow(tester, 'Enter IP Manually');
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoTextField), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
