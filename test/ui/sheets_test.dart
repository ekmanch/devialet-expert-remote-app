import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/ui/widgets/sheet_scaffold.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_text_field.dart';

import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/device_card.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_pressable.dart';
import 'package:devialet_expert_remote_app/ui/widgets/check_mark.dart';

import 'support/pump_control.dart';

/// Whether an amp-sheet row shows its check mark (the mark is always in
/// the tree, faded to 0 when unselected — the rows never reflow).
bool rowChecked(WidgetTester tester, Finder row) {
  final check = find.ancestor(of: find.descendant(of: row, matching: find.byType(CheckMark)), matching: find.byType(Opacity)).first;
  return tester.widget<Opacity>(check).opacity == 1;
}

/// The opacity of a row's content (dot + text), 0.5 for a silent, unselected amp.
double rowOpacity(WidgetTester tester, Finder row) {
  final content = find.ancestor(of: find.descendant(of: row, matching: find.byType(DeviceDot)), matching: find.byType(Opacity)).first;
  return tester.widget<Opacity>(content).opacity;
}

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

    testWidgets('manual IP: invalid stays; a valid one is a tagged, checked, waiting row until its first broadcast (3.9.3)', (tester) async {
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
      // No pumpAndSettle from here on: the card's waiting ring pulses.
      await settleSheet(tester);
      expect(find.text('Enter IP Address'), findsNothing);
      // A never-heard IP is a valid selection, shown *waiting* until a
      // broadcast from it arrives (docs/protocol.md, "Multi-amp").
      expect(readState(tester).selectedIp, '192.0.2.9');
      expect(readState(tester).isWaiting, isTrue);
      expect(textAt(tester, ControlKeys.deviceName), '192.0.2.9');
      expect(plainTextAt(tester, ControlKeys.deviceSub), 'Connecting\u2026');
      expect(textAt(tester, ControlKeys.dialValue), '\u2014');

      await openAmpSheet(tester);
      final row = find.byKey(ControlKeys.ampRow('192.0.2.9'));
      expect(row, findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('MANUAL')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Connecting\u2026')), findsOneWidget);
      expect(find.byKey(ControlKeys.ampGroupLabel), findsOneWidget);
      expect(rowChecked(tester, row), isTrue);
      expect(rowChecked(tester, find.byKey(ControlKeys.ampNoneRow)), isFalse, reason: 'None is not the selection');
      expect(rowChecked(tester, find.byKey(ControlKeys.ampRow('192.0.2.22'))), isFalse);

      // Its first broadcast: a plain online row, tag gone, card connected.
      containerOf(tester).read(ampStateProvider.notifier).ingest(syntheticReport(ip: '192.0.2.9', name: 'Manual'));
      await settleSheet(tester);
      expect(find.text('MANUAL'), findsNothing);
      expect(find.byKey(ControlKeys.ampGroupLabel), findsNothing);
      expect(find.descendant(of: row, matching: find.text('192.0.2.9 \u00b7 name unresolved')), findsOneWidget);
      expect(rowChecked(tester, row), isTrue);
      expect(textAt(tester, ControlKeys.deviceName), 'Manual');
      expect(textAt(tester, ControlKeys.deviceSub), '192.0.2.9 \u00b7 Connected');
    });

    testWidgets('3.9.0: the list is live while open — a new amp appears, a silent one drops under "Not responding" with "Last seen", and comes back', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      final owner = containerOf(tester).read(ampStateProvider.notifier);
      await openAmpSheet(tester);
      expect(find.byKey(ControlKeys.ampGroupLabel), findsNothing);
      owner.ingest(syntheticReport(ip: '192.0.2.30', name: 'Newcomer'));
      await settleSheet(tester);
      expect(find.text('Newcomer'), findsOneWidget);
      List<String> rows() => tester
          .widgetList<Widget>(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('control.ampRow.192')))
          .map((w) => (w.key! as ValueKey<String>).value.split('.').last)
          .toList();
      expect(rows(), ['22', '23', '24', '30']);

      owner.seedSilent('192.0.2.23');
      await settleSheet(tester);
      expect(find.text('NOT RESPONDING'), findsOneWidget);
      expect(rows(), ['22', '24', '30', '23'], reason: 'silent rows follow the online ones');
      final silentRow = find.byKey(ControlKeys.ampRow('192.0.2.23'));
      expect(find.descendant(of: silentRow, matching: find.text('192.0.2.23 \u00b7 Last seen just now')), findsOneWidget);
      expect(tester.widget<DeviceDot>(find.descendant(of: silentRow, matching: find.byType(DeviceDot))).state, DeviceDotState.off);
      expect(rowOpacity(tester, silentRow), 0.5, reason: 'dimmed, still tappable');
      expect(rowOpacity(tester, find.byKey(ControlKeys.ampRow('192.0.2.22'))), 1.0);

      owner.ingest(syntheticReport(ip: '192.0.2.23', name: 'Living Room'));
      await settleSheet(tester);
      expect(find.byKey(ControlKeys.ampGroupLabel), findsNothing);
      expect(rows(), ['22', '23', '24', '30']);
    });

    testWidgets('3.9.0: the chosen amp going silent stays checked with "Reconnecting…" and the pulsing ring; None is not checked', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      final owner = containerOf(tester).read(ampStateProvider.notifier);
      await openAmpSheet(tester);
      owner.seedSilent('192.0.2.22');
      await settleSheet(tester);
      expect(readState(tester).isWaiting, isTrue);
      final row = find.byKey(ControlKeys.ampRow('192.0.2.22'));
      expect(rowChecked(tester, row), isTrue);
      expect(rowChecked(tester, find.byKey(ControlKeys.ampNoneRow)), isFalse, reason: 'the 3.0.8 caveat, closed');
      expect(rowOpacity(tester, row), 1.0, reason: 'the selection is not dimmed');
      expect(find.descendant(of: row, matching: find.text('192.0.2.22 \u00b7 Reconnecting\u2026')), findsOneWidget);
      expect(tester.widget<DeviceDot>(find.descendant(of: row, matching: find.byType(DeviceDot))).state, DeviceDotState.waiting);
      expect(find.byKey(ControlKeys.ampGroupLabel), findsOneWidget);
      // Counter-run (manual, checklist 20): `noneSelected = !state.hasAmp`
      // in amp_sheet.dart turns the None assertion red.
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

    testWidgets(
      'a sheet opened on an Off amp shows dimmed, inert rows (3.5.1\'s row gate); live again on On — the owner does not gate openSheet',
      (tester) async {
        bool rowEnabled(String name) => tester
            .widget<AdaptivePressable>(
              find.ancestor(of: find.text(name), matching: find.byType(AdaptivePressable)).first,
            )
            .enabled;

        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.off));
        final notifier = containerOf(tester).read(ampStateProvider.notifier);
        // The trigger is inert while Off (its DimmedGroup blocks taps), so
        // open programmatically — the owner's slot is ungated by design.
        notifier.openSheet(SheetKind.source);
        await tester.pumpAndSettle();
        expect(find.text('Select source'), findsOneWidget);
        expect(opacityAt(tester, ControlKeys.sourceRows), 0.4);
        expect(rowEnabled('AirPlay'), isFalse);
        expect(find.text('AirPlay'), findsOneWidget, reason: 'dim, don\'t blank');
        await tapRow(tester, 'AirPlay', warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Select source'), findsOneWidget, reason: 'no On→not-On edge happened: the sheet stays');
        expect(readState(tester).activeSourceIndex, 0);

        // Counter-half (checklist 20): the same tap on the same row pops the
        // sheet and selects once the gate re-opens.
        seedFromControlView(notifier, ControlViewState.forScenario(DebugScenario.connected));
        await tester.pump();
        expect(opacityAt(tester, ControlKeys.sourceRows), 1.0);
        expect(rowEnabled('AirPlay'), isTrue);
        await tapRow(tester, 'AirPlay');
        await tester.pumpAndSettle();
        expect(find.text('Select source'), findsNothing);
        expect(readState(tester).activeSourceIndex, 3);
        expect(readState(tester).visibleSheet, SheetKind.none);
      },
    );

    testWidgets('long names elide in the trigger instead of overflowing', (tester) async {
      final state = ControlViewState.connectedFixture.copyWith(
        sources: const [SourceItem(index: 0, name: 'Chromecast Audio Extra Long')],
      );
      await pumpControl(tester, state: state);
      expect(tester.takeException(), isNull);
      expect(tester.widget<Text>(find.byKey(ControlKeys.sourceName)).overflow, TextOverflow.ellipsis);
    });
  });

  group('sheet visibility is owner-driven (3.8.2 / 3.0.6)', () {
    Future<void> openSourceSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(ControlKeys.sourceTrigger));
      await tester.pumpAndSettle();
      expect(find.text('Select source'), findsOneWidget);
      expect(readState(tester).visibleSheet, SheetKind.source);
    }

    /// What the engine sends for the Android back key / predictive-back
    /// commit: the `popRoute` navigation message. `tester.pageBack()`
    /// looks for a back-button widget, which a modal sheet has none of.
    Future<void> hardwareBack(WidgetTester tester) async {
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        SystemChannels.navigation.name,
        SystemChannels.navigation.codec.encodeMethodCall(const MethodCall('popRoute')),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    void expectClosed(WidgetTester tester) {
      expect(find.text('Select source'), findsNothing);
      expect(readState(tester).visibleSheet, SheetKind.none);
    }

    testWidgets('1. a row selection pops the sheet and the slot reads none', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openSourceSheet(tester);
      await tapRow(tester, 'AirPlay');
      await tester.pumpAndSettle();
      expectClosed(tester);
      expect(readState(tester).activeSourceIndex, 3);
    });

    for (final variant in UiVariant.values) {
      testWidgets('2. ${variant.name}: a barrier tap writes none back', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), variant: variant);
        await openSourceSheet(tester);
        await tester.tapAt(const Offset(195, 40)); // above the panel: the scrim
        await tester.pumpAndSettle();
        expectClosed(tester);
      });

      testWidgets('4. ${variant.name}: the hardware back key (popRoute) writes none back', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), variant: variant);
        await openSourceSheet(tester);
        await hardwareBack(tester);
        expectClosed(tester);
      });
    }

    testWidgets('3. android: a drag-down dismissal writes none back (the Cupertino popup has no drag dismissal)', (
      tester,
    ) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openSourceSheet(tester);
      await tester.fling(find.byType(SheetScaffold), const Offset(0, 600), 1500);
      await tester.pumpAndSettle();
      expectClosed(tester);
    });

    testWidgets('5. Navigator.maybePop from inside the sheet writes none back', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openSourceSheet(tester);
      await Navigator.of(tester.element(find.text('Select source'))).maybePop();
      await tester.pumpAndSettle();
      expectClosed(tester);
    });

    for (final scenario in [DebugScenario.off, DebugScenario.booting]) {
      testWidgets('6. power leaves On (${scenario.name}): the source sheet closes; the amp sheet does not', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
        final notifier = containerOf(tester).read(ampStateProvider.notifier);
        await openSourceSheet(tester);
        seedFromControlView(notifier, ControlViewState.forScenario(scenario));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expectClosed(tester);

        // Counter-half: the amp sheet is not on the power edge (KDE parity).
        seedFromControlView(notifier, ControlViewState.forScenario(DebugScenario.connected));
        await tester.pump();
        await openAmpSheet(tester);
        expect(readState(tester).visibleSheet, SheetKind.amp);
        seedFromControlView(notifier, ControlViewState.forScenario(scenario));
        await settleSheet(tester);
        expect(find.text('Choose Amplifier'), findsOneWidget);
        expect(readState(tester).visibleSheet, SheetKind.amp);
      });
    }

    testWidgets('7. the empty-state sheet (no amp) survives a connect; it closes only on the On→not-On edge', (
      tester,
    ) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notConnected));
      final notifier = containerOf(tester).read(ampStateProvider.notifier);
      await openSourceSheet(tester);
      expect(find.text('No sources available'), findsOneWidget);
      seedFromControlView(notifier, ControlViewState.forScenario(DebugScenario.connected));
      await tester.pumpAndSettle();
      expect(find.text('Select source'), findsOneWidget, reason: 'a level check would have popped it here');
      expect(find.text('AirPlay'), findsOneWidget, reason: 'the rows appeared in place');
      seedFromControlView(notifier, ControlViewState.forScenario(DebugScenario.off));
      await tester.pumpAndSettle();
      expectClosed(tester);
    });

    testWidgets('8. mutual exclusion: opening the amp sheet while the source sheet is up swaps them', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      final notifier = containerOf(tester).read(ampStateProvider.notifier);
      await openSourceSheet(tester);
      notifier.openSheet(SheetKind.amp);
      await settleSheet(tester);
      expect(find.text('Select source'), findsNothing);
      expect(find.text('Choose Amplifier'), findsOneWidget);
      expect(readState(tester).visibleSheet, SheetKind.amp, reason: 'the old route\'s completion did not clobber it');
      // And the swapped-in sheet is fully owned: a row pop writes none.
      await tapRow(tester, 'None');
      await tester.pumpAndSettle();
      expect(find.text('Choose Amplifier'), findsNothing);
      expect(readState(tester).visibleSheet, SheetKind.none);
    });

    testWidgets('9. the amp sheet is owned the same way: barrier tap and back key write none back', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openAmpSheet(tester);
      expect(readState(tester).visibleSheet, SheetKind.amp);
      await tester.tapAt(const Offset(195, 40));
      await settleSheet(tester);
      expect(find.text('Choose Amplifier'), findsNothing);
      expect(readState(tester).visibleSheet, SheetKind.none);
      await openAmpSheet(tester);
      await hardwareBack(tester);
      expect(find.text('Choose Amplifier'), findsNothing);
      expect(readState(tester).visibleSheet, SheetKind.none);
    });

    testWidgets('10. tearing the app down with a sheet up throws nothing', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openSourceSheet(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
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
