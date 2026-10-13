import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/power_button.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_tokens.dart';
import 'package:devialet_expert_remote_app/ui/widgets/stroke_icons.dart';

import 'support/pump_control.dart';

/// The round power button in isolation (alternate v44b / v47c–e).
///
/// Red proofs (run once, 2026-09-26): swapping the two `bootRing` token
/// values fails the light/dark colour pair; dropping the `BootRing` from
/// the stack fails "glyph + ring"; a 900 ms period under reduced motion
/// fails the 2.5 s case.
void main() {
  Finder ring() => find.byWidgetPredicate((w) => w is CustomPaint && w.painter is BootRingPainter);
  BootRingPainter painter(WidgetTester tester) => tester.widget<CustomPaint>(ring()).painter! as BootRingPainter;
  Finder glyph() => find.descendant(of: find.byKey(ControlKeys.powerIcon), matching: find.byType(StrokeIcon));
  AnimatedContainer circle(WidgetTester tester) => tester.widget<AnimatedContainer>(find.byType(AnimatedContainer));
  Color borderOf(WidgetTester tester) => ((circle(tester).decoration! as BoxDecoration).border! as Border).top.color;

  Widget button({
    PowerPhase power = PowerPhase.on,
    bool hasAmp = true,
    bool enabled = true,
    VoidCallback? onTap,
    Brightness brightness = Brightness.dark,
    UiVariant variant = UiVariant.android,
    bool reducedMotion = false,
  }) {
    Widget child = Center(child: PowerButton(power: power, hasAmp: hasAmp, enabled: enabled, onTap: onTap ?? () {}));
    if (reducedMotion) child = MediaQuery(data: const MediaQueryData(disableAnimations: true), child: child);
    return themed(child, brightness: brightness, variant: variant);
  }

  group('booting (style A)', () {
    for (final brightness in Brightness.values) {
      testWidgets('$brightness: the glyph stays and the outline is a ring in the theme\'s flat colour', (tester) async {
        await tester.pumpWidget(button(power: PowerPhase.booting, brightness: brightness));
        final t = AppTokens.forBrightness(brightness);
        expect(tester.widget<StrokeIcon>(glyph()).kind, StrokeIconKind.power);
        expect(ring(), findsOneWidget);
        // Literals, not the token: the token is what the widget reads, so
        // comparing against it could not catch a swapped palette.
        final dark = brightness == Brightness.dark;
        expect(painter(tester).color, dark ? const Color(0xFFE0B563) : const Color(0xFFF5C542));
        expect(borderOf(tester), dark ? const Color(0x2EE0B563) : const Color(0x47F5C542));
        // Light: the metallic-gold glyph; dark: flat amber, no mask.
        final mask = find.ancestor(of: glyph(), matching: find.byType(ShaderMask));
        expect(mask, brightness == Brightness.light ? findsOneWidget : findsNothing);
        if (brightness == Brightness.dark) expect(tester.widget<StrokeIcon>(glyph()).color, t.warningBright);
      });
    }

    testWidgets('the ring turns once per 0.9 s, clockwise', (tester) async {
      await tester.pumpWidget(button(power: PowerPhase.booting));
      expect(painter(tester).turns, 0);
      await tester.pump(const Duration(milliseconds: 450));
      expect(painter(tester).turns, closeTo(0.5, 0.01));
      await tester.pump(const Duration(milliseconds: 450));
      expect(painter(tester).turns, anyOf(closeTo(0, 0.01), closeTo(1, 0.01)));
    });

    testWidgets('reduced motion slows the ring to 2.5 s instead of stopping it', (tester) async {
      await tester.pumpWidget(button(power: PowerPhase.booting, reducedMotion: true));
      await tester.pump(const Duration(milliseconds: 450));
      expect(painter(tester).turns, closeTo(0.18, 0.01));
    });

    testWidgets('not booting: no ring, the plain border', (tester) async {
      await tester.pumpWidget(button());
      expect(ring(), findsNothing);
      expect(borderOf(tester), AppTokens.dark.divider);
    });
  });

  group('colours are the pre-spike pill\'s', () {
    testWidgets('on: text; off: textDim; no amp: text', (tester) async {
      final t = AppTokens.dark;
      await tester.pumpWidget(button());
      expect(tester.widget<StrokeIcon>(glyph()).color, t.text);
      await tester.pumpWidget(button(power: PowerPhase.off));
      expect(tester.widget<StrokeIcon>(glyph()).color, t.textDim);
      await tester.pumpWidget(button(hasAmp: false, enabled: false));
      expect(tester.widget<StrokeIcon>(glyph()).color, t.text);
    });

    for (final variant in UiVariant.values) {
      testWidgets('${variant.name}: pressed while on = danger, pressed while off = success', (tester) async {
        final t = AppTokens.dark;
        await tester.pumpWidget(button(variant: variant));
        var gesture = await tester.startGesture(tester.getCenter(find.byType(PowerButton)));
        await tester.pump(const Duration(milliseconds: 200));
        expect(borderOf(tester), t.danger);
        expect(tester.widget<StrokeIcon>(glyph()).color, t.danger);
        await gesture.up();
        await tester.pumpWidget(button(power: PowerPhase.off, variant: variant));
        await tester.pump(const Duration(milliseconds: 200));
        gesture = await tester.startGesture(tester.getCenter(find.byType(PowerButton)));
        await tester.pump(const Duration(milliseconds: 200));
        expect(borderOf(tester), t.success);
        expect(tester.widget<StrokeIcon>(glyph()).color, t.successBright);
        await gesture.up();
      });
    }
  });

  group('semantics and gate', () {
    testWidgets('the label is the old pill text per state', (tester) async {
      final handle = tester.ensureSemantics();
      for (final (power, hasAmp, label) in [
        (PowerPhase.on, true, 'Power Off'),
        (PowerPhase.off, true, 'Power On'),
        (PowerPhase.booting, true, 'Powering on…'),
        (PowerPhase.on, false, 'Power Off'),
      ]) {
        await tester.pumpWidget(button(power: power, hasAmp: hasAmp));
        expect(tester.getSemantics(find.byType(PowerButton)), isSemantics(label: label, isButton: true));
      }
      handle.dispose();
    });

    for (final variant in UiVariant.values) {
      testWidgets('${variant.name}: disabled swallows the tap, enabled fires once', (tester) async {
        var taps = 0;
        await tester.pumpWidget(button(enabled: false, onTap: () => taps++, variant: variant));
        await tester.tap(find.byType(PowerButton));
        expect(taps, 0);
        await tester.pumpWidget(button(onTap: () => taps++, variant: variant));
        await tester.tap(find.byType(PowerButton));
        expect(taps, 1);
      });
    }
  });
}
