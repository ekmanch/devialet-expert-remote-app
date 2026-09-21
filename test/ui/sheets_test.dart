import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_pressable.dart';

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
      // A never-heard IP is a valid selection, shown not connected until a
      // broadcast from it arrives (docs/protocol.md, "Multi-amp").
      expect(readState(tester).selectedIp, '192.0.2.9');
      expect(textAt(tester, ControlKeys.deviceName), 'No Amplifier');
      expect(textAt(tester, ControlKeys.deviceSub), 'Tap to connect');
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

    for (final scenario in [DebugScenario.off, DebugScenario.booting]) {
      testWidgets(
        'rows dim and go inert when the amp goes ${scenario.name} while the sheet is open; live again on On',
        (tester) async {
          bool rowEnabled(String name) => tester
              .widget<AdaptivePressable>(
                find.ancestor(of: find.text(name), matching: find.byType(AdaptivePressable)).first,
              )
              .enabled;

          await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
          await tester.tap(find.byKey(ControlKeys.sourceTrigger));
          await tester.pumpAndSettle();
          expect(opacityAt(tester, ControlKeys.sourceRows), 1.0);
          expect(rowEnabled('AirPlay'), isTrue);

          // The amp goes Off / Booting under the open sheet (Task 3.5.1).
          final notifier = containerOf(tester).read(ampStateProvider.notifier);
          seedFromControlView(notifier, ControlViewState.forScenario(scenario));
          await tester.pump();
          expect(opacityAt(tester, ControlKeys.sourceRows), 0.4);
          expect(rowEnabled('AirPlay'), isFalse);
          expect(find.text('AirPlay'), findsOneWidget, reason: 'dim, don\'t blank');
          // The row sits under an IgnorePointer, so the tap is expected to
          // miss; Booting animates forever, so a bounded pump, not settle.
          await tapRow(tester, 'AirPlay', warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Select source'), findsOneWidget, reason: 'the sheet stays open');
          expect(readState(tester).activeSourceIndex, 0);

          // Counter-test (checklist 20): the same tap on the same row pops the
          // sheet and selects once the gate re-opens — so the sheet staying
          // open above is the widget gate's doing, not the owner's (whose
          // check would still have let the unconditional pop run).
          seedFromControlView(notifier, ControlViewState.forScenario(DebugScenario.connected));
          await tester.pump();
          expect(opacityAt(tester, ControlKeys.sourceRows), 1.0);
          expect(rowEnabled('AirPlay'), isTrue);
          await tapRow(tester, 'AirPlay');
          await tester.pumpAndSettle();
          expect(find.text('Select source'), findsNothing);
          expect(readState(tester).activeSourceIndex, 3);
        },
      );
    }

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
