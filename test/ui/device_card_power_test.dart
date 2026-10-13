import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/device_card.dart';
import 'package:devialet_expert_remote_app/ui/control/power_button.dart';

import 'support/pump_control.dart';

/// Power on the amp card (alternate v44b): the card is two tap targets.
///
/// Red proofs (run once, 2026-09-26): `absorb: false` on the power's
/// `DimmedGroup` lets the no-amp tap fall through and open the sheet;
/// an overlay inset of 16 (padding without the border) fails the
/// geometry test by 1 dp; moving the circle into the Row (no overlay)
/// fails "a power tap does not open the sheet" on both variants.
void main() {
  Finder sheet() => find.text('Choose Amplifier');

  for (final variant in UiVariant.values) {
    group(variant.name, () {
      testWidgets('a power tap toggles power and never opens the amp sheet', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), variant: variant);
        await tester.tap(find.byKey(ControlKeys.powerButton));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 500));
        expect(readState(tester).power, PowerPhase.off);
        expect(readState(tester).visibleSheet, SheetKind.none);
        expect(sheet(), findsNothing);
      });

      testWidgets('a tap on the amp area opens the sheet and leaves power alone', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), variant: variant);
        await tester.tap(find.byKey(ControlKeys.deviceName));
        await settleSheet(tester);
        expect(sheet(), findsOneWidget);
        expect(readState(tester).power, PowerPhase.on);
      });

      testWidgets('booting: the inert circle swallows its tap (no toggle, no sheet)', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.booting), variant: variant);
        await tester.tap(find.byKey(ControlKeys.powerButton));
        await settleSheet(tester);
        expect(readState(tester).power, PowerPhase.booting);
        expect(sheet(), findsNothing);
      });

      testWidgets('no amp: the dimmed circle absorbs its tap (owner decision: no fall-through to the sheet)', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notConnected), variant: variant);
        expect(opacityAt(tester, ControlKeys.powerButton), 0.35);
        await tester.tap(find.byKey(ControlKeys.powerButton));
        await settleSheet(tester);
        expect(readState(tester).hasAmp, isFalse);
        expect(sheet(), findsNothing);
        // Counter-half: the amp area next to it still opens the sheet.
        await tester.tap(find.byKey(ControlKeys.deviceName));
        await settleSheet(tester);
        expect(sheet(), findsOneWidget);
      });
    });
  }

  testWidgets('geometry: the overlay circle sits exactly in the row\'s slot (padding + border from one set of constants)', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    final card = tester.getRect(find.byKey(ControlKeys.deviceCard));
    final power = tester.getRect(find.byKey(ControlKeys.powerButton));
    final divider = tester.getRect(find.byKey(ControlKeys.deviceDivider));
    expect(power.size, const Size(kPowerButtonSize, kPowerButtonSize));
    expect(card.right - power.right, DeviceCard.paddingH + DeviceCard.borderWidth);
    expect(power.center.dy, closeTo(card.center.dy, 0.01));
    expect(power.left - divider.right, DeviceCard.gap);
    expect(divider.size, const Size(1, DeviceCard.dividerHeight));
    expect(tester.getSize(find.byKey(ControlKeys.powerIcon)), const Size(kPowerGlyphSize, kPowerGlyphSize));
  });

  testWidgets('checklist 16: the power glyph does not move across on / off / booting', (tester) async {
    final positions = <Offset>{};
    for (final scenario in [DebugScenario.connected, DebugScenario.off, DebugScenario.booting]) {
      await pumpControl(tester, state: ControlViewState.forScenario(scenario));
      positions.add(tester.getTopLeft(find.byKey(ControlKeys.powerIcon)));
    }
    expect(positions, hasLength(1));
  });

  testWidgets('checklist 16: the mute glyph does not move between Mute and Unmute', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    final before = tester.getTopLeft(find.byKey(ControlKeys.muteIcon));
    await tester.tap(find.byKey(ControlKeys.muteButton));
    await tester.pump(const Duration(milliseconds: 200));
    expect(readState(tester).isMuted, isTrue);
    expect(tester.getTopLeft(find.byKey(ControlKeys.muteIcon)), before);
  });
}
