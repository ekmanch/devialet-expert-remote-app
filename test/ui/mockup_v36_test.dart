import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/control_screen.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_pressable.dart';
import 'package:devialet_expert_remote_app/ui/settings/settings_keys.dart';
import 'package:devialet_expert_remote_app/ui/settings/settings_screen.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_theme.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_tokens.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_typography.dart';
import 'package:devialet_expert_remote_app/ui/widgets/arcs.dart';
import 'package:devialet_expert_remote_app/ui/widgets/header_icon_button.dart';
import 'package:devialet_expert_remote_app/ui/widgets/section_label.dart';
import 'package:devialet_expert_remote_app/ui/widgets/stroke_icons.dart';

import 'support/pump_control.dart';
import 'support/pump_settings.dart';

/// The v19 → v36 mockup pass (Task 2.0.15). Each group names the mockup
/// version that introduced the rule. The test binding's OS brightness
/// defaults to *light*; dark-theme checks pin it.
void main() {
  void osBrightness(WidgetTester tester, Brightness b) {
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  Color borderColorOf(WidgetTester tester, Key key) =>
      ((tester.widget<Container>(find.byKey(key)).decoration! as BoxDecoration).border! as Border).top.color;

  group('tokens (v36 light accent)', () {
    test('light copperBright is #c79a2e; dark unchanged', () {
      expect(AppTokens.light.copperBright, const Color(0xFFC79A2E));
      expect(AppTokens.dark.copperBright, const Color(0xFFE3A06A));
    });

    test('the Cupertino primary follows the token', () {
      final primary = buildCupertinoTheme(const AppTypography(bodyFamily: null)).primaryColor as CupertinoDynamicColor;
      expect(primary.color, AppTokens.light.copperBright);
      expect(primary.darkColor, AppTokens.dark.copperBright);
    });
  });

  group('header (v36 bare icon buttons, bigger wordmark)', () {
    for (final (variant, size) in [(UiVariant.android, 15.0), (UiVariant.ios, 14.0)]) {
      testWidgets('${variant.name}: wordmark is $size px', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), variant: variant);
        expect(tester.widget<Text>(find.byKey(ControlKeys.wordmark)).style!.fontSize, size);
      });

      testWidgets('${variant.name}: the gear is a 23 px glyph in a bare 44 dp target overhanging by 10, no spring', (tester) async {
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected), variant: variant);
        final button = tester.widget<HeaderIconButton>(find.byKey(ControlKeys.gearButton));
        expect(button.overhang, 10);
        final icon = tester.widget<StrokeIcon>(
          find.descendant(of: find.byKey(ControlKeys.gearButton), matching: find.byType(StrokeIcon)),
        );
        expect(icon.kind, StrokeIconKind.gear);
        expect(icon.size, 23);
        final pressable = tester.widget<AdaptivePressable>(
          find.descendant(of: find.byKey(ControlKeys.gearButton), matching: find.byType(AdaptivePressable)),
        );
        expect(pressable.pressedScale, 1);
        expect(pressable.pressedOpacity, 1);
        expect(tester.getSize(find.byKey(ControlKeys.gearButton)), const Size(34, 44), reason: 'layout box');
        // The pressed disc is the only decoration; no surface/border/shadow.
        final box = tester.widget<Container>(
          find.descendant(of: find.byKey(ControlKeys.gearButton), matching: find.byType(Container)),
        );
        final decoration = box.decoration! as BoxDecoration;
        expect(decoration.border, isNull);
        expect(decoration.boxShadow, isNull);
        expect(decoration.color, isNull);
      });
    }

    testWidgets('the press disc appears while the finger is down', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      final gesture = await tester.startGesture(tester.getCenter(find.byKey(ControlKeys.gearButton)));
      await tester.pump(const Duration(milliseconds: 200));
      final box = tester.widget<Container>(
        find.descendant(of: find.byKey(ControlKeys.gearButton), matching: find.byType(Container)),
      );
      expect((box.decoration! as BoxDecoration).color, AppTokens.iconPressHighlight);
      await gesture.up();
    });
  });

  group('source card and footer (v36)', () {
    testWidgets('no "Active source" eyebrow; the name is 18/600', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      expect(find.text('Active source'), findsNothing);
      final name = tester.widget<Text>(find.byKey(ControlKeys.sourceName));
      expect(name.style!.fontSize, 18);
      expect(name.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('no footer status word; the device card carries the state', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      expect(find.text('Connected'), findsNothing);
      expect(textAt(tester, ControlKeys.deviceSub), '192.0.2.22 · Connected');
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.notConnected));
      expect(find.text('Not connected'), findsNothing);
      expect(textAt(tester, ControlKeys.deviceSub), 'Tap to connect');
    });
  });

  group('source sheet (v23/v26 cards, kinds, arcs, painted Spotify)', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byKey(ControlKeys.sourceTrigger));
      await tester.pumpAndSettle();
    }

    testWidgets('every source is a card with its kind label; the active card is outlined in copper', (tester) async {
      osBrightness(tester, Brightness.dark);
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await open(tester);
      final t = AppTheme.of(tester.element(find.byType(ControlScreen))).tokens;
      for (final kind in ['Digital in', 'Network', 'Roon', 'Apple AirPlay', 'Spotify Connect', 'Devialet AIR']) {
        expect(find.text(kind), findsOneWidget, reason: kind);
      }
      expect(borderColorOf(tester, ControlKeys.sourceCard(0)), t.copperBright);
      expect(borderColorOf(tester, ControlKeys.sourceCard(1)), t.divider);
      expect(find.byType(SheetArcs), findsOneWidget);
      // Spotify is painted, not the ◐ character.
      expect(find.text('◐'), findsNothing);
      expect(
        find.descendant(of: find.byKey(ControlKeys.sourceCard(4)), matching: find.byType(CustomPaint)),
        findsOneWidget,
      );
      expect(find.text('◉'), findsNWidgets(2), reason: 'Optical: trigger and card');
    });

    testWidgets('light: glyphs are gold-masked with a shadow copy underneath', (tester) async {
      osBrightness(tester, Brightness.light);
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await open(tester);
      expect(
        find.descendant(of: find.byKey(ControlKeys.sourceCard(0)), matching: find.byType(ShaderMask)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byKey(ControlKeys.sourceCard(4)), matching: find.byType(CustomPaint)),
        findsNWidgets(2),
        reason: 'shadow + masked ring',
      );
    });

    testWidgets('dark: no gold mask', (tester) async {
      osBrightness(tester, Brightness.dark);
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await open(tester);
      expect(
        find.descendant(of: find.byKey(ControlKeys.sourceCard(0)), matching: find.byType(ShaderMask)),
        findsNothing,
      );
    });
  });

  group('amp picker listening arcs (v36)', () {
    testWidgets('present on the list view, gone on the manual-IP view', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await openAmpSheet(tester);
      expect(find.byType(ListeningArcs), findsOneWidget);
      expect(find.byType(SheetArcs), findsNothing, reason: 'corner arcs are the source sheet only');
      await tester.tap(find.text('Enter IP Manually'));
      await tester.pumpAndSettle();
      expect(find.byType(ListeningArcs), findsNothing);
    });

    test('blink keyframes: .15 at rest, 1 at 30 %, staggered 250 ms per arc', () {
      expect(ListeningArcs.opacityAt(0, 0), closeTo(0.15, 1e-9));
      expect(ListeningArcs.opacityAt(0, 0.3), closeTo(1, 1e-9));
      expect(ListeningArcs.opacityAt(0, 0.65), closeTo(0.575, 1e-9));
      expect(ListeningArcs.opacityAt(1, 0.3 + 0.25 / 1.8), closeTo(1, 1e-9));
      expect(ListeningArcs.opacityAt(2, 0.3 + 0.5 / 1.8), closeTo(1, 1e-9));
      expect(ListeningArcs.opacityAt(1, 0.25 / 1.8), closeTo(0.15, 1e-9), reason: 'arc 2 rests at its own delay');
    });

    testWidgets('animates while shown; static at full opacity under reduced motion', (tester) async {
      ArcsPainter painter() => tester.widget<CustomPaint>(find.byType(CustomPaint)).painter! as ArcsPainter;
      await tester.pumpWidget(themed(const ListeningArcs()));
      final at0 = painter().colors.map((c) => c.a).toList();
      await tester.pump(const Duration(milliseconds: 540));
      final at540 = painter().colors.map((c) => c.a).toList();
      expect(at540[0], closeTo(1, 1e-6), reason: '30 % of 1.8 s');
      expect(at540, isNot(at0));

      await tester.pumpWidget(
        themed(const MediaQuery(data: MediaQueryData(disableAnimations: true), child: ListeningArcs())),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(painter().colors.map((c) => c.a), everyElement(closeTo(1, 1e-6)));
    });
  });

  group('settings (v28/v29/v30/v36)', () {
    testWidgets('no footer line', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Devialet Expert Pro Remote'), findsNothing);
    });

    testWidgets('android: the back arrow is a bare 30 px glyph overhanging left by 12', (tester) async {
      await pumpSettings(tester);
      final button = tester.widget<HeaderIconButton>(find.byKey(SettingsUiKeys.backButton));
      expect(button.overhang, -12);
      final glyph = tester.widget<Text>(
        find.descendant(of: find.byKey(SettingsUiKeys.backButton), matching: find.byType(Text)),
      );
      expect(glyph.data, '‹');
      expect(glyph.style!.fontSize, 30);
      expect(tester.getSize(find.byKey(SettingsUiKeys.backButton)), const Size(32, 44));
    });

    testWidgets('ios: the back control is the plain text colour in the dark theme too', (tester) async {
      osBrightness(tester, Brightness.dark);
      await pumpSettings(tester, variant: UiVariant.ios);
      final t = AppTheme.of(tester.element(find.byType(SettingsScreen))).tokens;
      expect(t.isDark, isTrue);
      expect(tester.widget<Text>(find.text('Remote')).style!.color, t.text);
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: numbers are neutral; the selected step is outlined in text colour', (tester) async {
        osBrightness(tester, brightness);
        await pumpSettings(tester);
        final t = AppTheme.of(tester.element(find.byType(SettingsScreen))).tokens;
        expect(t.brightness, brightness);
        final value = tester.widget<Text>(
          find.descendant(of: find.byKey(SettingsUiKeys.startupStepper.value), matching: find.byType(Text)),
        );
        expect(value.style!.color, t.text);
        final selected = tester.widget<Container>(
          find.descendant(of: find.byKey(SettingsUiKeys.stepOption(VolumeStepDb.one)), matching: find.byType(Container)),
        );
        expect(((selected.decoration! as BoxDecoration).border! as Border).top.color, t.text);
        final selectedText = tester.widget<Text>(find.text('1 dB'));
        expect(selectedText.style!.color, t.text);
        expect(selectedText.style!.fontWeight, FontWeight.w600);
      });
    }

    testWidgets('light: settings headings are gold-gradient bold; control headings stay faint', (tester) async {
      osBrightness(tester, Brightness.light);
      await pumpSettings(tester);
      final t = AppTheme.of(tester.element(find.byType(SettingsScreen))).tokens;
      final label = find.descendant(of: find.byType(SettingsScreen), matching: find.byWidgetPredicate((w) => w is SectionLabel && w.text == 'Volume Limits'));
      expect(find.descendant(of: label, matching: find.byType(ShaderMask)), findsOneWidget);
      final text = tester.widget<Text>(find.descendant(of: label, matching: find.byType(Text)));
      expect(text.style!.fontWeight, FontWeight.w700);
      expect(text.style!.color, t.copperBright, reason: 'the mask source; the gradient paints over it');

      await tester.tap(find.byKey(SettingsUiKeys.backButton));
      await tester.pumpAndSettle();
      final control = find.byWidgetPredicate((w) => w is SectionLabel && w.text == 'Volume');
      expect(find.descendant(of: control, matching: find.byType(ShaderMask)), findsNothing);
      final controlText = tester.widget<Text>(find.descendant(of: control, matching: find.byType(Text)));
      expect(controlText.style!.color, t.textFaint);
      expect(controlText.style!.fontWeight, FontWeight.w600);
    });

    testWidgets('dark: settings headings are flat copper bold, no gradient', (tester) async {
      osBrightness(tester, Brightness.dark);
      await pumpSettings(tester);
      final t = AppTheme.of(tester.element(find.byType(SettingsScreen))).tokens;
      final label = find.byWidgetPredicate((w) => w is SectionLabel && w.text == 'About');
      expect(find.descendant(of: label, matching: find.byType(ShaderMask)), findsNothing);
      final text = tester.widget<Text>(find.descendant(of: label, matching: find.byType(Text)));
      expect(text.style!.color, t.copperBright);
      expect(text.style!.fontWeight, FontWeight.w700);
    });

    testWidgets('descriptions and sheet subtitles read in textDim (v26 contrast)', (tester) async {
      await pumpSettings(tester);
      final t = AppTheme.of(tester.element(find.byType(SettingsScreen))).tokens;
      expect(tester.widget<Text>(find.text('Lowest volume possible to set')).style!.color, t.textDim);
      await tester.tap(find.byKey(SettingsUiKeys.backButton));
      await tester.pumpAndSettle();
      await openAmpSheet(tester);
      expect(tester.widget<Text>(find.text('Amplifiers found on your network')).style!.color, t.textDim);
      expect(tester.widget<Text>(find.text("Don't connect to any amplifier")).style!.color, t.textDim);
    });
  });
}
