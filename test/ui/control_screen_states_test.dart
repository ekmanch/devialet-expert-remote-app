import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/device_card.dart';
import 'package:devialet_expert_remote_app/ui/widgets/ring_spinner.dart';
import 'package:devialet_expert_remote_app/ui/widgets/stroke_icons.dart';

import 'support/pump_control.dart';

/// Expected rendering per scenario — actual == expected per state, not
/// "it didn't crash" (checklist item 20).
class _Expected {
  const _Expected({
    required this.name,
    required this.sub,
    required this.dot,
    required this.value,
    required this.unitVisible,
    required this.muteLabel,
    required this.muteIcon,
    required this.powerLabel,
    required this.spinner,
    required this.dialWrap,
    required this.actionRow,
    required this.muteButton,
    required this.sourceTrigger,
    required this.footer,
    required this.sourceName,
    required this.dialSourceLabel,
  });

  final String name;
  final String sub;
  final DeviceDotState dot;
  final String value;
  final bool unitVisible;
  final String muteLabel;
  final StrokeIconKind muteIcon;
  final String powerLabel;
  final bool spinner;
  final double dialWrap;
  final double actionRow;
  final double muteButton;
  final double sourceTrigger;
  final String footer;
  final String sourceName;
  final String dialSourceLabel;
}

const _connected = _Expected(
  name: 'Devialet Expert 140 Pro',
  sub: '192.0.2.22 \u00b7 Connected',
  dot: DeviceDotState.connected,
  value: '\u221225.0',
  unitVisible: true,
  muteLabel: 'Mute',
  muteIcon: StrokeIconKind.speaker,
  powerLabel: 'Power Off',
  spinner: false,
  dialWrap: 1.0,
  actionRow: 1.0,
  muteButton: 1.0,
  sourceTrigger: 1.0,
  footer: 'Connected',
  sourceName: 'Optical 1',
  dialSourceLabel: 'OPTICAL 1',
);

const _noAmp = _Expected(
  name: 'No Amplifier',
  sub: 'Tap to connect',
  dot: DeviceDotState.none,
  value: '\u2014',
  unitVisible: false,
  muteLabel: 'Mute',
  muteIcon: StrokeIconKind.speaker,
  powerLabel: 'Power Off',
  spinner: false,
  dialWrap: 0.4,
  actionRow: 0.4,
  muteButton: 1.0,
  sourceTrigger: 0.5,
  footer: 'Not connected',
  sourceName: 'No source',
  dialSourceLabel: 'NO SOURCE',
);

final Map<DebugScenario, _Expected> _expected = {
  DebugScenario.connected: _connected,
  DebugScenario.off: const _Expected(
    name: 'Devialet Expert 140 Pro',
    sub: '192.0.2.22 \u00b7 Connected',
    dot: DeviceDotState.off,
    value: '\u221225.0',
    unitVisible: true,
    muteLabel: 'Mute',
    muteIcon: StrokeIconKind.speaker,
    powerLabel: 'Power On',
    spinner: false,
    dialWrap: 0.4,
    actionRow: 1.0,
    muteButton: 0.4,
    sourceTrigger: 0.4,
    footer: 'Connected',
    sourceName: 'Optical 1',
    dialSourceLabel: 'OPTICAL 1',
  ),
  DebugScenario.booting: const _Expected(
    name: 'Devialet Expert 140 Pro',
    sub: 'Booting\u2026',
    dot: DeviceDotState.booting,
    value: '\u221225.0',
    unitVisible: true,
    muteLabel: 'Mute',
    muteIcon: StrokeIconKind.speaker,
    powerLabel: 'Powering on\u2026',
    spinner: true,
    dialWrap: 0.4,
    actionRow: 1.0,
    muteButton: 0.4,
    sourceTrigger: 0.4,
    footer: 'Connected',
    sourceName: 'Optical 1',
    dialSourceLabel: 'OPTICAL 1',
  ),
  DebugScenario.notResponding: _noAmp,
  DebugScenario.notConnected: _noAmp,
  DebugScenario.muted: const _Expected(
    name: 'Devialet Expert 140 Pro',
    sub: '192.0.2.22 \u00b7 Connected',
    dot: DeviceDotState.connected,
    value: 'Muted',
    unitVisible: false,
    muteLabel: 'Unmute',
    muteIcon: StrokeIconKind.speakerMuted,
    powerLabel: 'Power Off',
    spinner: false,
    dialWrap: 1.0,
    actionRow: 1.0,
    muteButton: 1.0,
    sourceTrigger: 1.0,
    footer: 'Connected',
    sourceName: 'Optical 1',
    dialSourceLabel: 'OPTICAL 1',
  ),
};

void main() {
  for (final variant in UiVariant.values) {
    for (final scenario in DebugScenario.values) {
      final e = _expected[scenario]!;
      testWidgets('${scenario.name} renders as expected in the ${variant.name} variant', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(scenario), variant: variant);

        expect(textAt(tester, ControlKeys.deviceName), e.name);
        expect(textAt(tester, ControlKeys.deviceSub), e.sub);
        expect(tester.widget<DeviceDot>(find.byKey(ControlKeys.deviceDot)).state, e.dot);
        expect(textAt(tester, ControlKeys.dialValue), e.value);
        expect(visibilityOf(tester, ControlKeys.dialUnit), e.unitVisible);
        expect(textAt(tester, ControlKeys.muteLabel), e.muteLabel);
        final muteIcon = find.descendant(of: find.byKey(ControlKeys.muteIcon), matching: find.byType(StrokeIcon));
        expect(tester.widget<StrokeIcon>(muteIcon).kind, e.muteIcon);
        expect(textAt(tester, ControlKeys.powerLabel), e.powerLabel);
        final spinner = find.descendant(of: find.byKey(ControlKeys.powerIcon), matching: find.byType(RingSpinner));
        expect(spinner, e.spinner ? findsOneWidget : findsNothing);
        expect(opacityAt(tester, ControlKeys.dialWrap), e.dialWrap);
        expect(opacityAt(tester, ControlKeys.actionRow), e.actionRow);
        expect(opacityAt(tester, ControlKeys.muteButton), e.muteButton);
        expect(opacityAt(tester, ControlKeys.sourceTrigger), e.sourceTrigger);
        expect(textAt(tester, ControlKeys.footer), e.footer);
        expect(textAt(tester, ControlKeys.sourceName), e.sourceName);
        expect(textAt(tester, ControlKeys.dialSourceLabel), e.dialSourceLabel);
      });
    }
  }

  group('gating covers every input path (checklist 6)', () {
    testWidgets('volume, mute and source are inert while Off; last-known text stays', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.off));
      await tester.tap(find.byKey(ControlKeys.volPlus), warnIfMissed: false);
      await tester.tap(find.byKey(ControlKeys.muteButton), warnIfMissed: false);
      await tester.tap(find.byKey(ControlKeys.sourceTrigger), warnIfMissed: false);
      await tester.pump();
      expect(readState(tester).volumeDb, -25.0);
      expect(readState(tester).isMuted, isFalse);
      expect(find.text('Select source'), findsNothing);
      expect(textAt(tester, ControlKeys.dialValue), '\u221225.0');
    });

    testWidgets('power is inert while Booting', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.booting));
      await tester.tap(find.byKey(ControlKeys.powerButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(readState(tester).power, PowerPhase.booting);
    });

    testWidgets('power flips on → off, then the off → on edge enters Booting (3.2.0)', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await tester.tap(find.byKey(ControlKeys.powerButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(textAt(tester, ControlKeys.powerLabel), 'Power On');
      expect(tester.widget<DeviceDot>(find.byKey(ControlKeys.deviceDot)).state, DeviceDotState.off);
      // The optimistic Off must be confirmed before a boot can start.
      seedFromControlView(containerOf(tester).read(ampStateProvider.notifier), ControlViewState.forScenario(DebugScenario.off));
      await tester.pump();
      await tester.tap(find.byKey(ControlKeys.powerButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(textAt(tester, ControlKeys.powerLabel), 'Powering on\u2026');
      expect(textAt(tester, ControlKeys.deviceSub), 'Booting\u2026');
      expect(tester.widget<DeviceDot>(find.byKey(ControlKeys.deviceDot)).state, DeviceDotState.booting);
      expect(find.descendant(of: find.byKey(ControlKeys.powerIcon), matching: find.byType(RingSpinner)), findsOneWidget);
    });

    testWidgets('no amp: power and volume inert, source trigger still opens the empty state', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notConnected));
      await tester.tap(find.byKey(ControlKeys.powerButton), warnIfMissed: false);
      await tester.tap(find.byKey(ControlKeys.volMinus), warnIfMissed: false);
      await tester.pump();
      expect(readState(tester).hasAmp, isFalse);
      expect(textAt(tester, ControlKeys.dialValue), '\u2014');
      await tester.tap(find.byKey(ControlKeys.sourceTrigger));
      await tester.pumpAndSettle();
      expect(find.text('No sources available'), findsOneWidget);
      expect(find.text('No amplifier connected'), findsOneWidget);
    });

    testWidgets('connected: buttons step 1 dB and mute toggles', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await tester.tap(find.byKey(ControlKeys.volPlus));
      await tester.pump();
      expect(textAt(tester, ControlKeys.dialValue), '\u221224.0');
      await tester.tap(find.byKey(ControlKeys.volMinus));
      await tester.tap(find.byKey(ControlKeys.volMinus));
      await tester.pump();
      expect(textAt(tester, ControlKeys.dialValue), '\u221226.0');
      await tester.tap(find.byKey(ControlKeys.muteButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(textAt(tester, ControlKeys.dialValue), 'Muted');
      expect(visibilityOf(tester, ControlKeys.dialUnit), isFalse);
      expect(textAt(tester, ControlKeys.muteLabel), 'Unmute');
    });
  });

  testWidgets('debug bar cycles scenarios in both directions', (tester) async {
    await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
    await tester.ensureVisible(find.byKey(ControlKeys.debugNext));
    await tester.tap(find.byKey(ControlKeys.debugNext));
    await tester.pump();
    expect(textAt(tester, ControlKeys.powerLabel), 'Power On');
    await tester.tap(find.byKey(ControlKeys.debugPrev));
    await tester.tap(find.byKey(ControlKeys.debugPrev));
    await tester.pump();
    expect(textAt(tester, ControlKeys.dialValue), 'Muted');
  });
}
