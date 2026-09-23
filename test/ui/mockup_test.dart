import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/amp_sheet.dart';
import 'package:devialet_expert_remote_app/ui/control/control_screen.dart';
import 'package:devialet_expert_remote_app/ui/control/device_card.dart';
import 'package:devialet_expert_remote_app/ui/control/manual_entry_glyph.dart';
import 'package:devialet_expert_remote_app/ui/control/source_glyph.dart';
import 'package:devialet_expert_remote_app/ui/control/source_glyphs.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_pressable.dart';
import 'package:devialet_expert_remote_app/ui/settings/settings_keys.dart';
import 'package:devialet_expert_remote_app/ui/settings/settings_screen.dart';
import 'package:devialet_expert_remote_app/ui/settings/theme_glyph.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_theme.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_tokens.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_typography.dart';
import 'package:devialet_expert_remote_app/ui/widgets/arcs.dart';
import 'package:devialet_expert_remote_app/ui/widgets/check_mark.dart';
import 'package:devialet_expert_remote_app/ui/widgets/painted_glyph.dart';
import 'package:devialet_expert_remote_app/ui/widgets/header_icon_button.dart';
import 'package:devialet_expert_remote_app/ui/widgets/section_label.dart';
import 'package:devialet_expert_remote_app/ui/widgets/stroke_icons.dart';

import 'support/pump_control.dart';
import 'support/pump_settings.dart';

/// Guards for the mockup ports: the v19 → v36 pass (Task 2.0.15) and the
/// rounds since (2.0.16–2.0.19, mockups v39). Each group names the mockup
/// version that introduced its rule; the current mockup files are named
/// in TODO.md "Task 2.0.x". The test binding's OS brightness defaults to
/// *light*; dark-theme checks pin it.
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
    testWidgets('no "Active source" eyebrow; the name is 15/600 like the amp name (owner mockup update 2026-09-23)', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      expect(find.text('Active source'), findsNothing);
      final name = tester.widget<Text>(find.byKey(ControlKeys.sourceName));
      expect(name.style!.fontSize, 15);
      expect(name.style!.fontSize, tester.widget<Text>(find.byKey(ControlKeys.deviceName)).style!.fontSize);
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

  group('source sheet (v23/v26 cards, kinds, arcs, painted glyphs)', () {
    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byKey(ControlKeys.sourceTrigger));
      await tester.pumpAndSettle();
    }

    final glyphPaint = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is SourceGlyphPainter);

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
      // Every glyph is painted, never the mockup's character (the
      // phone's font renders ◉ ◍ ◈ tiny and ◇ large — 2026-09-23 S25).
      for (final ch in ['◉', '◫', '◍', '◈', '◐', '◇']) {
        expect(find.text(ch), findsNothing, reason: ch);
      }
      final kinds = <SourceGlyphKind>[];
      for (final i in const [0, 1, 2, 3, 4, 14]) {
        final paint = tester.widget<CustomPaint>(
          find.descendant(of: find.byKey(ControlKeys.sourceCard(i)), matching: glyphPaint),
        );
        expect(paint.size, const Size.square(15 * 1.05), reason: 'card $i: one shared box');
        kinds.add((paint.painter! as SourceGlyphPainter).kind);
      }
      expect(kinds, SourceGlyphKind.values.where((k) => k != SourceGlyphKind.none));
      final trigger = tester.widget<CustomPaint>(
        find.descendant(of: find.byKey(ControlKeys.sourceTrigger), matching: glyphPaint),
      );
      expect(trigger.size, const Size.square(16 * 1.05));
      expect((trigger.painter! as SourceGlyphPainter).kind, SourceGlyphKind.optical);
      // The selected-row tick is painted at 18, never the ✓ character.
      expect(find.text('\u2713'), findsNothing);
      expect(find.byType(CheckMark), findsNWidgets(6), reason: 'one per card, hidden by opacity when unselected');
      expect(tester.widgetList<CheckMark>(find.byType(CheckMark)).map((c) => c.size), everyElement(18));
    });

    testWidgets('light: glyphs are gold-masked with a shadow copy underneath', (tester) async {
      osBrightness(tester, Brightness.light);
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      await open(tester);
      expect(
        find.descendant(of: find.byKey(ControlKeys.sourceCard(0)), matching: find.byType(ShaderMask)),
        findsOneWidget,
      );
      for (final i in const [0, 1, 2, 3, 4, 14]) {
        final paints = tester
            .widgetList<CustomPaint>(
              find.descendant(of: find.byKey(ControlKeys.sourceCard(i)), matching: glyphPaint),
            )
            .map((p) => p.painter! as SourceGlyphPainter)
            .toList();
        expect(paints.map((p) => p.shadow), [AppTokens.glyphGoldShadow, null], reason: 'card $i: shadow + masked');
      }
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

  group('amp picker and device card dots (2026-09-23 sizing)', () {
    testWidgets('the card dot and every amp-row dot are 13 in a 16 leading slot; the tick is painted', (tester) async {
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      expect(tester.widget<DeviceDot>(find.byKey(ControlKeys.deviceDot)).size, DeviceDot.defaultSize);
      expect(DeviceDot.defaultSize, 13);
      await openAmpSheet(tester);
      final dots = tester.widgetList<DeviceDot>(find.descendant(of: find.byType(AmpSheet), matching: find.byType(DeviceDot)));
      expect(dots, isNotEmpty);
      expect(dots.map((d) => d.size), everyElement(13));
      expect(find.text('✓'), findsNothing);
      expect(find.descendant(of: find.byType(AmpSheet), matching: find.byType(CheckMark)), findsAtLeastNWidgets(2));
    });

    for (final brightness in Brightness.values) {
      testWidgets('${brightness.name}: "Enter IP Manually" is a painted keyboard in the shared box, bare, gold like the rest', (tester) async {
        osBrightness(tester, brightness);
        await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
        await openAmpSheet(tester);
        expect(find.text('\u2328'), findsNothing, reason: 'no ⌨ character');
        final row = find.ancestor(of: find.text('Enter IP Manually'), matching: find.byType(AdaptivePressable)).first;
        final glyph = tester.widget<PaintedGlyph>(find.descendant(of: row, matching: find.byType(PaintedGlyph)));
        expect(glyph.size, 15);
        final paints = tester
            .widgetList<CustomPaint>(find.descendant(of: row, matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ManualEntryGlyphPainter)))
            .toList();
        expect(glyph.opticalScale, ManualEntryGlyph.opticalScale);
        expect(paints.map((p) => p.size), everyElement(const Size.square(15 * 1.05 * ManualEntryGlyph.opticalScale)));
        if (brightness == Brightness.light) {
          expect(paints.map((p) => (p.painter! as ManualEntryGlyphPainter).shadow), [AppTokens.glyphGoldShadow, null], reason: 'shadow + gold mask');
          expect(find.descendant(of: row, matching: find.byType(ShaderMask)), findsOneWidget);
        } else {
          final t = AppTheme.of(tester.element(find.byType(ControlScreen))).tokens;
          expect(paints.single.painter!, isA<ManualEntryGlyphPainter>().having((p) => p.color, 'color', t.copperBright));
        }
        // Bare on the row: no bordered chip around the glyph.
        final boxes = tester.widgetList<Container>(find.descendant(of: row, matching: find.byType(Container)));
        expect(boxes.where((c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).border != null), isEmpty);
        // Same leading slot as the amp rows: every title starts at one x.
        final amps = ControlViewState.forScenario(DebugScenario.connected).knownAmps.map((a) => a.displayName);
        final x = ['None', ...amps, 'Enter IP Manually']
            .map((s) => tester.getTopLeft(find.descendant(of: find.byType(AmpSheet), matching: find.text(s))).dx)
            .toSet();
        expect(x, hasLength(1), reason: 'titles line up: $x');
        // The trailing chevron is painted at the tick's size, not the › character.
        expect(find.descendant(of: find.byType(AmpSheet), matching: find.text('›')), findsNothing);
        expect(tester.widget<ChevronMark>(find.descendant(of: row, matching: find.byType(ChevronMark))).size, 18);
      });
    }

    testWidgets('chevrons are painted on the source trigger and the settings rows too', (tester) async {
      await pumpSettings(tester);
      expect(find.text('\u203a'), findsNothing);
      expect(find.byType(ChevronMark), findsAtLeastNWidgets(2), reason: 'theme row, GitHub row');
      await tester.tap(find.byKey(SettingsUiKeys.backButton));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byKey(ControlKeys.sourceTrigger), matching: find.byType(ChevronMark)), findsOneWidget);
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
    final themeGlyph = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is ThemeGlyphPainter);

    Future<void> openThemeSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(SettingsUiKeys.themeRow));
      await tester.pumpAndSettle();
    }

    testWidgets('theme sheet glyphs are painted in the shared box, never the mockup characters', (tester) async {
      osBrightness(tester, Brightness.dark);
      await pumpSettings(tester);
      await openThemeSheet(tester);
      for (final ch in ['\u25d0', '\u263e', '\u2600']) {
        expect(find.text(ch), findsNothing, reason: ch);
      }
      for (final mode in AppThemeMode.values) {
        final paint = tester.widget<CustomPaint>(
          find.descendant(of: find.byKey(SettingsUiKeys.themeOption(mode)), matching: themeGlyph),
        );
        expect(paint.size, const Size.square(15 * 1.05), reason: '${mode.name}: one shared box');
        expect((paint.painter! as ThemeGlyphPainter).mode, mode);
        expect((paint.painter! as ThemeGlyphPainter).shadow, isNull, reason: 'dark: flat, no shadow');
      }
    });

    testWidgets('light: the sun\'s gold radiates from its centre; the other glyphs keep the mockup\'s off-centre', (tester) async {
      osBrightness(tester, Brightness.light);
      await pumpSettings(tester);
      await openThemeSheet(tester);
      PaintedGlyph glyphOf(AppThemeMode mode) => tester.widget<PaintedGlyph>(
        find.descendant(of: find.byKey(SettingsUiKeys.themeOption(mode)), matching: find.byType(PaintedGlyph)),
      );
      expect(glyphOf(AppThemeMode.light).gradientCenter, Alignment.center);
      expect(glyphOf(AppThemeMode.light).gradientRadius, 0.5);
      expect(glyphOf(AppThemeMode.dark).gradientCenter, AppTokens.glyphGoldCenter);
      expect(glyphOf(AppThemeMode.system).gradientRadius, 0.75);
    });

    testWidgets('the selected-row tick is painted at 18 in every sheet, never the ✓ character', (tester) async {
      await pumpSettings(tester);
      await openThemeSheet(tester);
      expect(find.text('\u2713'), findsNothing);
      final themeTick = tester.widget<CheckMark>(
        find.descendant(of: find.byKey(SettingsUiKeys.themeOption(AppThemeMode.system)), matching: find.byType(CheckMark)),
      );
      expect(themeTick.size, 18);
      expect(find.byType(CheckMark), findsNWidgets(3), reason: 'one per row, hidden by opacity when unselected');
      expect(tester.widgetList<CheckMark>(find.byType(CheckMark)).map((c) => c.size), everyElement(18));
    });

    testWidgets('light: theme sheet glyphs are gold-masked with a shadow copy underneath', (tester) async {
      osBrightness(tester, Brightness.light);
      await pumpSettings(tester);
      await openThemeSheet(tester);
      for (final mode in AppThemeMode.values) {
        final paints = tester
            .widgetList<CustomPaint>(
              find.descendant(of: find.byKey(SettingsUiKeys.themeOption(mode)), matching: themeGlyph),
            )
            .map((p) => p.painter! as ThemeGlyphPainter)
            .toList();
        expect(paints.map((p) => p.shadow), [AppTokens.glyphGoldShadow, null], reason: '${mode.name}: shadow + masked');
      }
    });

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

    testWidgets('light: settings and control headings are gold-gradient bold (control matched 2026-09-23)', (tester) async {
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
      for (final name in ['Volume', 'Source']) {
        final control = find.byWidgetPredicate((w) => w is SectionLabel && w.text == name);
        expect(find.descendant(of: control, matching: find.byType(ShaderMask)), findsOneWidget, reason: name);
        final controlText = tester.widget<Text>(find.descendant(of: control, matching: find.byType(Text)));
        expect(controlText.style!.color, t.copperBright, reason: name);
        expect(controlText.style!.fontWeight, FontWeight.w700, reason: name);
      }
    });

    testWidgets('dark: control headings are flat copper bold like Settings', (tester) async {
      osBrightness(tester, Brightness.dark);
      await pumpControl(tester, state: ControlViewState.forScenario(DebugScenario.connected));
      final t = AppTheme.of(tester.element(find.byType(ControlScreen))).tokens;
      final control = find.byWidgetPredicate((w) => w is SectionLabel && w.text == 'Source');
      expect(find.descendant(of: control, matching: find.byType(ShaderMask)), findsNothing);
      final text = tester.widget<Text>(find.descendant(of: control, matching: find.byType(Text)));
      expect(text.style!.color, t.copperBright);
      expect(text.style!.fontWeight, FontWeight.w700);
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
