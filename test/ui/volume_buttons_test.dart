import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/volume_buttons.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_tokens.dart';
import 'package:devialet_expert_remote_app/ui/widgets/stroke_icons.dart';

import 'support/pump_control.dart';

/// A host that can flip `enabled` under a held button (Task 3.6.1).
class _Host extends StatefulWidget {
  const _Host({super.key, required this.enabled, required this.onMinus, required this.onPlus});

  final bool enabled;
  final bool Function() onMinus;
  final bool Function() onPlus;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late bool enabled = widget.enabled;

  void set(bool value) => setState(() => enabled = value);

  @override
  Widget build(BuildContext context) =>
      VolumeButtons(enabled: enabled, onMinus: widget.onMinus, onPlus: widget.onPlus, isMuted: false, onMute: () {});
}

/// Task 3.5.1: the VOL −/+ buttons are inert by their own `enabled` flag,
/// with **no** `DimmedGroup` above them — the regression the audit found
/// (a re-parented button would have been live while Off). The `enabled:
/// true` half is the checklist-20 counter-test: the same tree, the same
/// tap, and the callback *does* fire, so the silence above is the gate's.
///
/// Task 3.6.1: hold-to-repeat — 0 / 300 / 400 / 500 ms (unmeasured KDE
/// constants, `kVolumeHoldDelay` / `kVolumeRepeatInterval`), release stops,
/// a bound (`false` from the step) ends the chain, disabling mid-hold
/// stops it, and a screen reader's tap (no pointer) still steps once.
///
/// Alternate v47b/v47c: mute is the middle circle — its icon is always the
/// muted speaker and only the circle's colours say "active"; the circles
/// have no text, so the semantics labels are checked here. Red proofs (run
/// once, 2026-09-26): returning the divider border while muted fails
/// "accent while muted"; swapping the icon per state fails "icon constant".
void main() {
  Widget row({required bool enabled, required bool isMuted, VoidCallback? onMute, UiVariant variant = UiVariant.android}) =>
      themed(
        VolumeButtons(enabled: enabled, onMinus: () => true, onPlus: () => true, isMuted: isMuted, onMute: onMute ?? () {}),
        variant: variant,
      );
  AnimatedContainer muteCircle(WidgetTester tester) => tester.widget<AnimatedContainer>(
    find.descendant(of: find.byKey(ControlKeys.muteButton), matching: find.byType(AnimatedContainer)),
  );
  StrokeIcon muteIcon(WidgetTester tester) => tester.widget<StrokeIcon>(
    find.descendant(of: find.byKey(ControlKeys.muteIcon), matching: find.byType(StrokeIcon)),
  );

  group('mute circle (v47b)', () {
    testWidgets('the icon is the muted speaker in both states; the accent colours mark active', (tester) async {
      final t = AppTokens.dark;
      await tester.pumpWidget(row(enabled: true, isMuted: false));
      expect(muteIcon(tester).kind, StrokeIconKind.speakerMuted);
      expect(muteIcon(tester).color, t.text);
      var d = muteCircle(tester).decoration! as BoxDecoration;
      expect((d.color, (d.border! as Border).top.color, d.shape), (t.surface, t.divider, BoxShape.circle));

      await tester.pumpWidget(row(enabled: true, isMuted: true));
      expect(muteIcon(tester).kind, StrokeIconKind.speakerMuted, reason: 'the icon names the function, not the state');
      expect(muteIcon(tester).color, t.copperBright);
      d = muteCircle(tester).decoration! as BoxDecoration;
      expect((d.color, (d.border! as Border).top.color), (t.accentTint(0.14), t.copperDim));
    });

    testWidgets('semantics: "Mute" / "Unmute" with the toggled state; −/+ are "Volume down" / "Volume up"', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(row(enabled: true, isMuted: false));
      expect(tester.getSemantics(find.byKey(ControlKeys.muteButton)), isSemantics(label: 'Mute', isButton: true, isToggled: false, hasTapAction: true));
      expect(tester.getSemantics(find.byKey(ControlKeys.volMinus)), isSemantics(label: 'Volume down', isButton: true, hasTapAction: true));
      expect(tester.getSemantics(find.byKey(ControlKeys.volPlus)), isSemantics(label: 'Volume up', isButton: true, hasTapAction: true));
      await tester.pumpWidget(row(enabled: true, isMuted: true));
      expect(tester.getSemantics(find.byKey(ControlKeys.muteButton)), isSemantics(label: 'Unmute', isToggled: true));
      handle.dispose();
    });

    for (final variant in UiVariant.values) {
      testWidgets('${variant.name}: disabled mute swallows the tap; enabled fires once', (tester) async {
        var taps = 0;
        await tester.pumpWidget(row(enabled: false, isMuted: false, onMute: () => taps++, variant: variant));
        await tester.tap(find.byKey(ControlKeys.muteButton));
        expect(taps, 0);
        await tester.pumpWidget(row(enabled: true, isMuted: false, onMute: () => taps++, variant: variant));
        await tester.tap(find.byKey(ControlKeys.muteButton));
        expect(taps, 1);
      });
    }

    testWidgets('geometry: three 66 dp circles, 34 dp apart, 26 dp icons (v47c)', (tester) async {
      await tester.pumpWidget(row(enabled: true, isMuted: false));
      for (final key in [ControlKeys.volMinus, ControlKeys.muteButton, ControlKeys.volPlus]) {
        expect(tester.getSize(find.byKey(key)), const Size(66, 66), reason: '$key');
      }
      expect(tester.getRect(find.byKey(ControlKeys.muteButton)).left - tester.getRect(find.byKey(ControlKeys.volMinus)).right, 34);
      expect(tester.getRect(find.byKey(ControlKeys.volPlus)).left - tester.getRect(find.byKey(ControlKeys.muteButton)).right, 34);
      expect(tester.getSize(find.byKey(ControlKeys.muteIcon)), const Size(26, 26));
      expect(muteIcon(tester).strokeWidth, 1.8);
    });
  });

  for (final variant in UiVariant.values) {
    testWidgets('disabled VOL buttons swallow taps by themselves (${variant.name})', (tester) async {
      var minus = 0;
      var plus = 0;
      await tester.pumpWidget(
        themed(
          VolumeButtons(enabled: false, onMinus: () => ++minus > 0, onPlus: () => ++plus > 0, isMuted: false, onMute: () {}),
          variant: variant,
        ),
      );
      await tester.tap(find.byKey(ControlKeys.volMinus));
      await tester.tap(find.byKey(ControlKeys.volPlus));
      await tester.pump();
      expect((minus, plus), (0, 0));
    });

    testWidgets('counter-test: the same taps reach the callbacks exactly once each when enabled (${variant.name})', (
      tester,
    ) async {
      var minus = 0;
      var plus = 0;
      await tester.pumpWidget(
        themed(
          VolumeButtons(enabled: true, onMinus: () => ++minus > 0, onPlus: () => ++plus > 0, isMuted: false, onMute: () {}),
          variant: variant,
        ),
      );
      await tester.tap(find.byKey(ControlKeys.volMinus));
      await tester.tap(find.byKey(ControlKeys.volPlus));
      await tester.tap(find.byKey(ControlKeys.volPlus));
      await tester.pump();
      expect((minus, plus), (1, 2), reason: 'press steps, the tap that follows the press must not step again');
    });

    testWidgets('hold: one step at once, then at 300, 400, 500 ms; release stops (${variant.name})', (tester) async {
      var plus = 0;
      await tester.pumpWidget(
        themed(VolumeButtons(enabled: true, onMinus: () => true, onPlus: () => ++plus > 0, isMuted: false, onMute: () {}), variant: variant),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(ControlKeys.volPlus)));
      await tester.pump();
      expect(plus, 1, reason: 'steps on press, not on release');
      await tester.pump(const Duration(milliseconds: 299));
      expect(plus, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(plus, 2, reason: 'first repeat at kVolumeHoldDelay (Qt autoRepeatDelay semantics)');
      await tester.pump(const Duration(milliseconds: 100));
      expect(plus, 3);
      await tester.pump(const Duration(milliseconds: 100));
      expect(plus, 4);
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(plus, 4, reason: 'released: no further ticks, and the tap after the press does not step');
    });

    testWidgets('a step that reports "did not move" ends the hold at the bound (${variant.name})', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        themed(VolumeButtons(enabled: true, onMinus: () => true, onPlus: () => ++calls < 3, isMuted: false, onMute: () {}), variant: variant),
      );
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(ControlKeys.volPlus)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 3, reason: 'the third call returned false and nothing was retried');
      await gesture.up();
      await tester.pump();
    });

    testWidgets('disabling mid-hold stops the chain; counter-half: kept enabled, it keeps ticking (${variant.name})', (
      tester,
    ) async {
      for (final disable in [true, false]) {
        var plus = 0;
        // A key per pass: the same host type would otherwise keep its
        // (now disabled) state across the two pumps.
        await tester.pumpWidget(
          themed(
            _Host(key: ValueKey(disable), enabled: true, onMinus: () => true, onPlus: () => ++plus > 0),
            variant: variant,
          ),
        );
        final gesture = await tester.startGesture(tester.getCenter(find.byKey(ControlKeys.volPlus)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(plus, 3, reason: 'ticks at 0, 300, 400');
        if (disable) tester.state<_HostState>(find.byType(_Host)).set(false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(plus, disable ? 3 : 6, reason: 'disable=$disable');
        await gesture.up();
        await tester.pump();
      }
    });

    testWidgets('a screen reader tap (no pointer) steps exactly once (${variant.name})', (tester) async {
      final handle = tester.ensureSemantics();
      var plus = 0;
      await tester.pumpWidget(
        themed(VolumeButtons(enabled: true, onMinus: () => true, onPlus: () => ++plus > 0, isMuted: false, onMute: () {}), variant: variant),
      );
      // The tap action lives on the variant's own gesture widget (InkWell /
      // GestureDetector), not on the keyed wrapper.
      final node = tester.getSemantics(
        find.descendant(
          of: find.byKey(ControlKeys.volPlus),
          matching: variant == UiVariant.ios ? find.byType(GestureDetector) : find.byType(InkWell),
        ),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue, reason: 'the tap action must exist');
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      expect(plus, 1);
      handle.dispose();
    });
  }
}
