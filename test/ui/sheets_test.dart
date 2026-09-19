import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';

import 'support/pump_control.dart';

void main() {
  Future<void> openAmpSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(ControlKeys.deviceCard));
    await tester.pumpAndSettle();
  }

  group('amp sheet', () {
    testWidgets('None first, then a divider, then amps; unresolved amp is tagged', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openAmpSheet(tester);
      expect(find.text('Choose Amplifier'), findsOneWidget);
      expect(find.text("Don't connect to any amplifier"), findsOneWidget);
      final none = tester.getTopLeft(find.text('None'));
      final first = tester.getTopLeft(find.text('Devialet Expert 140 Pro').last);
      final third = tester.getTopLeft(find.text('Devialet-ETH'));
      expect(none.dy, lessThan(first.dy));
      expect(first.dy, lessThan(third.dy));
      expect(find.text('My Devialet \u00b7 192.0.2.22'), findsOneWidget);
      expect(find.text('192.0.2.24 \u00b7 name unresolved'), findsOneWidget);
      expect(find.text('Enter IP Manually'), findsOneWidget);
    });

    testWidgets('choosing None disconnects; choosing an amp connects to it', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openAmpSheet(tester);
      await tapRow(tester, 'None');
      await tester.pumpAndSettle();
      expect(find.text('Choose Amplifier'), findsNothing);
      expect(textAt(tester, ControlKeys.deviceName), 'No Amplifier');
      expect(textAt(tester, ControlKeys.footer), 'Not connected');

      await openAmpSheet(tester);
      await tapRow(tester, 'Devialet Expert 220 Pro');
      await tester.pumpAndSettle();
      expect(textAt(tester, ControlKeys.deviceName), 'Devialet Expert 220 Pro');
      expect(textAt(tester, ControlKeys.deviceSub), '192.0.2.23 \u00b7 Connected');
      expect(textAt(tester, ControlKeys.footer), 'Connected');
    });

    testWidgets('manual IP: invalid stays, valid connects as an unresolved amp', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notConnected));
      await openAmpSheet(tester);
      await tapRow(tester, 'Enter IP Manually');
      await tester.pumpAndSettle();
      expect(find.text('Enter IP Address'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), '999.1.1.1');
      await tester.pump();
      await tapRow(tester, 'Connect');
      await tester.pumpAndSettle();
      expect(find.text('Enter IP Address'), findsOneWidget, reason: 'invalid IP does nothing');

      await tester.enterText(find.byType(EditableText), '192.0.2.9');
      await tester.pump();
      await tapRow(tester, 'Connect');
      await tester.pumpAndSettle();
      expect(find.text('Enter IP Address'), findsNothing);
      expect(textAt(tester, ControlKeys.deviceName), 'New Amplifier');
      expect(textAt(tester, ControlKeys.deviceSub), '192.0.2.9 \u00b7 Connected');
    });

    testWidgets('"Back to list" returns to the list view', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openAmpSheet(tester);
      await tapRow(tester, 'Enter IP Manually');
      await tester.pumpAndSettle();
      await tester.tap(find.text('\u2039 Back to list'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Amplifier'), findsOneWidget);
    });
  });

  group('source sheet', () {
    testWidgets('selecting a row updates trigger and dial label and closes', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await tester.tap(find.byKey(ControlKeys.sourceTrigger));
      await tester.pumpAndSettle();
      expect(find.text('Select source'), findsOneWidget);
      expect(find.text('Devialet Expert 140 Pro'), findsNWidgets(2), reason: 'header and sheet subtitle');
      for (final name in ['UPnP', 'Roon Ready', 'AirPlay', 'Spotify', 'AIR']) {
        expect(find.text(name), findsOneWidget);
      }
      await tapRow(tester, 'AirPlay');
      await tester.pumpAndSettle();
      expect(find.text('Select source'), findsNothing);
      expect(textAt(tester, ControlKeys.sourceName), 'AirPlay');
      expect(textAt(tester, ControlKeys.dialSourceLabel), 'AIRPLAY');
      expect(readState(tester).activeSourceIndex, 3);
    });

    testWidgets('long names elide in the trigger instead of overflowing', (tester) async {
      final state = ControlViewState.connectedFixture.copyWith(
        sources: const [SourceItem(index: 0, name: 'Chromecast Audio Extra Long')],
      );
      await pumpControl(tester, state: state);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.byKey(ControlKeys.sourceName)).overflow, TextOverflow.ellipsis);
    });
  });
}
