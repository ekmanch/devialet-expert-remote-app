import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/control_screen.dart';
import 'package:devialet_expert_remote_app/ui/control/device_card.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_pressable.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_theme.dart';
import 'package:devialet_expert_remote_app/ui/widgets/dimmed_group.dart';
import 'package:devialet_expert_remote_app/ui/control/power_button.dart';
import 'package:devialet_expert_remote_app/ui/widgets/stroke_icons.dart';

import 'support/pump_control.dart';

/// Expected rendering per scenario — actual == expected per state, not
/// "it didn't crash" (checklist item 20). Alternate layout: mute and power
/// are icon-only circles, so their names are semantics labels (`null` =
/// the group is dimmed and excluded from the semantics tree), the mute
/// icon is always the muted speaker and "active" is the accent colours,
/// power's booting cue is the ring, and power dims by itself (0.35, no
/// amp / waiting) now that it lives on the card.
class _Expected {
  const _Expected({
    required this.name,
    required this.sub,
    required this.dot,
    required this.value,
    required this.unitVisible,
    required this.muteLabel,
    required this.muteActive,
    required this.powerLabel,
    required this.bootRing,
    required this.power,
    required this.dialWrap,
    required this.sourceTrigger,
    required this.volButtonsEnabled,
    required this.sourceName,
    required this.dialSourceLabel,
  });

  final String name;
  final String sub;
  final DeviceDotState dot;
  final String value;
  final bool unitVisible;
  final String? muteLabel;
  final bool muteActive;
  final String? powerLabel;
  final bool bootRing;
  final double power;
  final double dialWrap;
  final double sourceTrigger;

  /// The VOL −/+ buttons' own `enabled` flag (Task 3.5.1), independent of
  /// the ancestor `DimmedGroup` measured by [dialWrap].
  final bool volButtonsEnabled;
  final String sourceName;
  final String dialSourceLabel;
}

const _connected = _Expected(
  name: 'Devialet Expert 140 Pro',
  sub: '192.0.2.22',
  dot: DeviceDotState.connected,
  value: '\u221225.0',
  unitVisible: true,
  muteLabel: 'Mute',
  muteActive: false,
  powerLabel: 'Power Off',
  bootRing: false,
  power: 1.0,
  dialWrap: 1.0,
  sourceTrigger: 1.0,
  volButtonsEnabled: true,
  sourceName: 'Optical 1',
  dialSourceLabel: 'OPTICAL 1',
);

const _noAmp = _Expected(
  name: 'No Amplifier',
  sub: 'Tap to connect',
  dot: DeviceDotState.none,
  value: '\u2014',
  unitVisible: false,
  muteLabel: null,
  muteActive: false,
  powerLabel: null,
  bootRing: false,
  power: 0.35,
  dialWrap: 0.4,
  sourceTrigger: 0.5,
  volButtonsEnabled: false,
  sourceName: 'No source',
  dialSourceLabel: 'NO SOURCE',
);

final Map<DebugScenario, _Expected> _expected = {
  DebugScenario.connected: _connected,
  DebugScenario.off: const _Expected(
    name: 'Devialet Expert 140 Pro',
    sub: '192.0.2.22',
    dot: DeviceDotState.off,
    value: '\u221225.0',
    unitVisible: true,
    muteLabel: null,
    muteActive: false,
    powerLabel: 'Power On',
    bootRing: false,
    power: 1.0,
    dialWrap: 0.4,
    sourceTrigger: 0.4,
    volButtonsEnabled: false,
    sourceName: 'Optical 1',
    dialSourceLabel: 'OPTICAL 1',
  ),
  DebugScenario.booting: const _Expected(
    name: 'Devialet Expert 140 Pro',
    sub: 'Booting\u2026',
    dot: DeviceDotState.booting,
    value: '\u221225.0',
    unitVisible: true,
    muteLabel: null,
    muteActive: false,
    powerLabel: 'Powering on\u2026',
    bootRing: true,
    power: 1.0,
    dialWrap: 0.4,
    sourceTrigger: 0.4,
    volButtonsEnabled: false,
    sourceName: 'Optical 1',
    dialSourceLabel: 'OPTICAL 1',
  ),
  // v44 / Task 3.9.0: the chosen amp went silent — still named, the
  // pulsing accent ring, "Reconnecting…" in the accent colour, no reading,
  // every control inert exactly as with no amp.
  DebugScenario.notResponding: const _Expected(
    name: 'Devialet Expert 140 Pro',
    sub: 'Reconnecting\u2026 \u00b7 192.0.2.22',
    dot: DeviceDotState.waiting,
    value: '\u2014',
    unitVisible: false,
    muteLabel: null,
    muteActive: false,
    powerLabel: null,
    bootRing: false,
    power: 0.35,
    dialWrap: 0.4,
    sourceTrigger: 0.5,
    volButtonsEnabled: false,
    sourceName: 'No source',
    dialSourceLabel: 'NO SOURCE',
  ),
  DebugScenario.notConnected: _noAmp,
  DebugScenario.muted: const _Expected(
    name: 'Devialet Expert 140 Pro',
    sub: '192.0.2.22',
    dot: DeviceDotState.connected,
    value: 'Muted',
    unitVisible: false,
    muteLabel: 'Unmute',
    muteActive: true,
    powerLabel: 'Power Off',
    bootRing: false,
    power: 1.0,
    dialWrap: 1.0,
    sourceTrigger: 1.0,
    volButtonsEnabled: true,
    sourceName: 'Optical 1',
    dialSourceLabel: 'OPTICAL 1',
  ),
};

Finder powerGlyph() => find.descendant(of: find.byKey(ControlKeys.powerIcon), matching: find.byType(StrokeIcon));
Finder bootRing() => find.descendant(
  of: find.byKey(ControlKeys.powerButton),
  matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BootRingPainter),
);
/// The semantics node lives on the button itself, not on the dimming
/// wrapper that carries the key (`getSemantics` walks *up* from a
/// render object without a node).
Finder powerNode() => find.descendant(of: find.byKey(ControlKeys.powerButton), matching: find.byType(PowerButton));

Color muteBorderOf(WidgetTester tester) {
  final circle = find.descendant(of: find.byKey(ControlKeys.muteButton), matching: find.byType(AnimatedContainer));
  return ((tester.widget<AnimatedContainer>(circle).decoration! as BoxDecoration).border! as Border).top.color;
}

void main() {
  for (final variant in UiVariant.values) {
    for (final scenario in DebugScenario.values) {
      final e = _expected[scenario]!;
      testWidgets('${scenario.name} renders as expected in the ${variant.name} variant', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpControl(tester, state: ControlViewState.forScenario(scenario), variant: variant);
        final t = AppTheme.of(tester.element(find.byType(ControlScreen))).tokens;

        expect(textAt(tester, ControlKeys.deviceName), e.name);
        expect(plainTextAt(tester, ControlKeys.deviceSub), e.sub);
        expect(tester.widget<DeviceDot>(find.byKey(ControlKeys.deviceDot)).state, e.dot);
        expect(textAt(tester, ControlKeys.dialValue), e.value);
        expect(visibilityOf(tester, ControlKeys.dialUnit), e.unitVisible);
        // Mute: the icon never changes; the accent colours are the state.
        final muteIcon = find.descendant(of: find.byKey(ControlKeys.muteIcon), matching: find.byType(StrokeIcon));
        expect(tester.widget<StrokeIcon>(muteIcon).kind, StrokeIconKind.speakerMuted);
        expect(tester.widget<StrokeIcon>(muteIcon).color, e.muteActive ? t.copperBright : t.text);
        expect(muteBorderOf(tester), e.muteActive ? t.copperDim : t.divider);
        if (e.muteLabel != null) {
          expect(tester.getSemantics(find.byKey(ControlKeys.muteButton)), isSemantics(label: e.muteLabel, isButton: true, isToggled: e.muteActive));
        }
        // Power: the glyph is always there; booting adds the ring, never a spinner.
        expect(tester.widget<StrokeIcon>(powerGlyph()).kind, StrokeIconKind.power);
        expect(bootRing(), e.bootRing ? findsOneWidget : findsNothing);
        if (e.powerLabel != null) {
          expect(tester.getSemantics(powerNode()), isSemantics(label: e.powerLabel, isButton: true));
        }
        expect(opacityAt(tester, ControlKeys.powerButton), e.power);
        expect(opacityAt(tester, ControlKeys.dialWrap), e.dialWrap);
        expect(opacityAt(tester, ControlKeys.sourceTrigger), e.sourceTrigger);
        // The buttons' own gate, not the group's (Task 3.5.1).
        for (final key in [ControlKeys.volMinus, ControlKeys.volPlus]) {
          final pressable = find.descendant(of: find.byKey(key), matching: find.byType(AdaptivePressable));
          expect(tester.widget<AdaptivePressable>(pressable).enabled, e.volButtonsEnabled, reason: '$key');
        }
        expect(textAt(tester, ControlKeys.sourceName), e.sourceName);
        expect(textAt(tester, ControlKeys.dialSourceLabel), e.dialSourceLabel);
        handle.dispose();
      });
    }
  }

  group('waiting (3.9.0, v44)', () {
    testWidgets('the card keeps the name at full strength, the status word is the accent colour, the IP is not', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notResponding));
      final t = AppTheme.of(tester.element(find.byType(ControlScreen))).tokens;
      final sub = tester.widget<Text>(find.byKey(ControlKeys.deviceSub)).textSpan! as TextSpan;
      final parts = sub.children!.cast<TextSpan>();
      expect(parts.map((p) => p.text), ['Reconnecting\u2026', ' \u00b7 192.0.2.22']);
      expect(parts.first.style!.color, t.copperBright);
      expect(parts.last.style?.color, isNull, reason: 'inherits the dim base');
      expect(sub.style!.color, t.textDim);
      // Not dimmed like "No Amplifier": the info column's DimmedGroup is off.
      final info = find.ancestor(of: find.byKey(ControlKeys.deviceName), matching: find.byType(DimmedGroup)).first;
      expect(tester.widget<DimmedGroup>(info).dimmed, isFalse);
    });

    testWidgets('a never-heard selection reads "Connecting…" alone under the IP as its title', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notConnected));
      containerOf(tester).read(ampStateProvider.notifier).addManualAmp('192.0.2.99');
      await tester.pump();
      expect(textAt(tester, ControlKeys.deviceName), '192.0.2.99');
      expect(plainTextAt(tester, ControlKeys.deviceSub), 'Connecting\u2026');
      expect(tester.widget<DeviceDot>(find.byKey(ControlKeys.deviceDot)).state, DeviceDotState.waiting);
      expect(textAt(tester, ControlKeys.dialValue), '\u2014');
    });

    testWidgets('every entry point is inert while waiting; the source trigger still opens the empty state', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notResponding));
      await tester.tap(find.byKey(ControlKeys.powerButton), warnIfMissed: false);
      await tester.tap(find.byKey(ControlKeys.volMinus), warnIfMissed: false);
      await tester.tap(find.byKey(ControlKeys.volPlus), warnIfMissed: false);
      await tester.tap(find.byKey(ControlKeys.muteButton), warnIfMissed: false);
      await tester.pump();
      final state = readState(tester);
      expect(state.isWaiting, isTrue);
      expect((state.power, state.isMuted, state.volumeDb), (PowerPhase.off, false, null));
      expect(textAt(tester, ControlKeys.dialValue), '\u2014');
      await tester.tap(find.byKey(ControlKeys.sourceTrigger));
      // No pumpAndSettle: the waiting ring pulses for as long as it is shown.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('No sources available'), findsOneWidget);
    });

    testWidgets('the waiting ring pulses 1 → 0.3 on a 900 ms leg; the booting dot on 550 ms; both hold still under reduced motion', (tester) async {
      double opacity() => tester.widget<FadeTransition>(find.byType(FadeTransition)).opacity.value;
      await tester.pumpWidget(themed(const DeviceDot(state: DeviceDotState.waiting)));
      expect(opacity(), 1.0);
      await tester.pump(kWaitingPulseLeg);
      expect(opacity(), closeTo(0.3, 1e-6), reason: 'one leg = half the mockup\'s 1.8 s cycle (checklist 15)');
      await tester.pump(kWaitingPulseLeg);
      expect(opacity(), closeTo(1.0, 1e-6));
      await tester.pumpWidget(themed(const DeviceDot(state: DeviceDotState.booting)));
      await tester.pump(kDotPulseLeg);
      expect(opacity(), closeTo(0.35, 1e-6));
      for (final state in [DeviceDotState.waiting, DeviceDotState.booting]) {
        await tester.pumpWidget(
          themed(MediaQuery(data: const MediaQueryData(disableAnimations: true), child: DeviceDot(state: state))),
        );
        await tester.pump(kWaitingPulseLeg);
        expect(opacity(), 1.0, reason: '$state holds still under reduced motion');
      }
    });
  });

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
      final handle = tester.ensureSemantics();
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await tester.tap(find.byKey(ControlKeys.powerButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSemantics(powerNode()), isSemantics(label: 'Power On'));
      expect(tester.widget<DeviceDot>(find.byKey(ControlKeys.deviceDot)).state, DeviceDotState.off);
      // The optimistic Off must be confirmed before a boot can start.
      seedFromControlView(
        containerOf(tester).read(ampStateProvider.notifier),
        ControlViewState.forScenario(DebugScenario.off),
      );
      await tester.pump();
      await tester.tap(find.byKey(ControlKeys.powerButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSemantics(powerNode()), isSemantics(label: 'Powering on\u2026'));
      expect(textAt(tester, ControlKeys.deviceSub), 'Booting\u2026');
      expect(tester.widget<DeviceDot>(find.byKey(ControlKeys.deviceDot)).state, DeviceDotState.booting);
      expect(bootRing(), findsOneWidget);
      expect(tester.widget<StrokeIcon>(powerGlyph()).kind, StrokeIconKind.power, reason: 'the glyph stays under the ring');
      handle.dispose();
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

    testWidgets('connected: buttons step the configured size (the fixture\'s 0.5 dB, not the 1 dB default) and mute toggles', (
      tester,
    ) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await tester.tap(find.byKey(ControlKeys.volPlus));
      await tester.pump();
      expect(textAt(tester, ControlKeys.dialValue), '\u221224.5');
      await tester.tap(find.byKey(ControlKeys.volMinus));
      await tester.tap(find.byKey(ControlKeys.volMinus));
      await tester.pump();
      expect(textAt(tester, ControlKeys.dialValue), '\u221225.5');
      await tester.tap(find.byKey(ControlKeys.muteButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(textAt(tester, ControlKeys.dialValue), 'Muted');
      expect(visibilityOf(tester, ControlKeys.dialUnit), isFalse);
      final t = AppTheme.of(tester.element(find.byType(ControlScreen))).tokens;
      expect(muteBorderOf(tester), t.copperDim, reason: 'the circle lights up; the icon does not change');
    });
  });
}
