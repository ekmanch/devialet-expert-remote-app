import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/ui/widgets/sheet_scaffold.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_text_field.dart';

import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_pressable.dart';

import 'support/pump_control.dart';

void main() {
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
      expect(textAt(tester, ControlKeys.deviceSub), 'Tap to connect');

      await openAmpSheet(tester);
      await tapRow(tester, 'Devialet Expert 220 Pro');
      await tester.pumpAndSettle();
      expect(textAt(tester, ControlKeys.deviceName), 'Devialet Expert 220 Pro');
      expect(textAt(tester, ControlKeys.deviceSub), '192.0.2.23 \u00b7 Connected');
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

    testWidgets('the entry view has a bare back chevron beside the title, no "Back to list" line; it returns to the list', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openAmpSheet(tester);
      expect(find.byKey(ControlKeys.sheetBack), findsNothing, reason: 'list view: no back control');
      await tapRow(tester, 'Enter IP Manually');
      await tester.pumpAndSettle();
      expect(find.text('\u2039 Back to list'), findsNothing);
      expect(find.text('Connect to an amplifier by its address'), findsOneWidget, reason: 'subtitle stays');
      final back = find.byKey(ControlKeys.sheetBack);
      expect(tester.getSize(back), const Size(32, 44), reason: '44 dp box overhanging the content edge by 12');
      final title = find.text('Enter IP Address');
      expect(tester.getTopLeft(title).dx, greaterThanOrEqualTo(tester.getTopRight(back).dx), reason: 'title after the chevron');
      expect((tester.getCenter(back).dy - tester.getCenter(title).dy).abs(), lessThan(1), reason: 'chevron on the title line');
      final subtitle = find.text('Connect to an amplifier by its address');
      expect((tester.getTopLeft(subtitle).dx - tester.getTopLeft(title).dx).abs(), lessThan(1), reason: 'subtitle indented under the title');
      // Bare: no bordered/filled chip around the chevron (the mockup's boxed .sheet-back is not ported — owner).
      final boxes = tester.widgetList<Container>(find.descendant(of: back, matching: find.byType(Container)));
      expect(boxes.where((c) => c.decoration is BoxDecoration && ((c.decoration! as BoxDecoration).border != null || (c.decoration! as BoxDecoration).color != null)), isEmpty);
      await tester.tap(back);
      await settleSheet(tester);
      expect(find.text('Choose Amplifier'), findsOneWidget);
    });

    testWidgets('"Air" is shown as AIR in the trigger and the sheet; AirPlay and the raw name are untouched', (tester) async {
      final base = ControlViewState.forScenario(DebugScenario.connected);
      final state = base.copyWith(
        sources: [
          const SourceItem(index: 3, name: 'AirPlay'),
          const SourceItem(index: 14, name: 'Devialet Air'),
          const SourceItem(index: 5, name: 'air'),
        ],
        activeSourceIndex: 14,
      );
      await pumpControl(tester, state: state);
      expect(textAt(tester, ControlKeys.sourceName), 'Devialet AIR');
      await tester.tap(find.byKey(ControlKeys.sourceTrigger));
      await tester.pumpAndSettle();
      expect(find.text('AirPlay'), findsOneWidget);
      // The kind label "Devialet AIR" also matches by text, so count titles (15 px) only.
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'Devialet AIR' && w.style?.fontSize == 15),
        findsNWidgets(2),
        reason: 'trigger (behind) + card',
      );
      expect(find.text('AIR'), findsOneWidget);
      expect(find.text('air'), findsNothing);
      expect(find.text('Devialet Air'), findsNothing);
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

  group('keyboard (2026-09-23)', () {
    for (final variant in UiVariant.values) {
      testWidgets('${variant.name}: the manual-IP field stays above the keyboard; the sheet never grows past the screen', (tester) async {
        await pumpControl(tester, variant: variant, state: ControlViewState.forScenario(DebugScenario.connected));
        await openAmpSheet(tester);
        await tester.tap(find.text('Enter IP Manually'));
        await settleSheet(tester);
        final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final fieldBefore = tester.getRect(find.byType(AdaptiveTextField));
        expect(fieldBefore.bottom, lessThan(screenHeight));

        const keyboard = 320.0;
        tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
        await settleSheet(tester);
        final field = tester.getRect(find.byType(AdaptiveTextField));
        expect(field.bottom, lessThanOrEqualTo(screenHeight - keyboard), reason: 'field visible above the keyboard');
        expect(field.top, greaterThanOrEqualTo(0));
        expect(tester.getRect(find.byType(SheetScaffold)).top, greaterThanOrEqualTo(0), reason: 'sheet not pushed off the top');

        tester.view.viewInsets = FakeViewPadding.zero;
        await settleSheet(tester);
        expect(tester.getRect(find.byType(AdaptiveTextField)), fieldBefore, reason: 'back where it was once the keyboard goes');
      });
    }
  });
}
