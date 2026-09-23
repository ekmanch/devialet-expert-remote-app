import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/app_info.dart';
import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_store.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/control_screen.dart';
import 'package:devialet_expert_remote_app/ui/settings/settings_keys.dart';
import 'package:devialet_expert_remote_app/ui/settings/settings_screen.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_theme.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_tokens.dart';

import '../support/pump_control.dart';
import '../support/pump_settings.dart';

class _ThrowingStore extends InMemorySettingsStore {
  @override
  Future<void> write(String key, Object? value) async => throw const SettingsWriteException('nope');
}

void main() {
  group('navigation', () {
    testWidgets('android: the gear pushes a Material route with the icon back button and a 22px title', (tester) async {
      await pumpSettings(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(ModalRoute.of(tester.element(find.byType(SettingsScreen))), isA<MaterialPageRoute<void>>());
      expect(tester.widget<Text>(find.byKey(SettingsUiKeys.title)).style!.fontSize, 22);
      expect(find.text('Remote'), findsNothing);
      await tester.tap(find.byKey(SettingsUiKeys.backButton));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.byType(ControlScreen), findsOneWidget);
    });

    testWidgets('ios: a Cupertino route with the "‹ Remote" back control and a centred 16px title', (tester) async {
      await pumpSettings(tester, variant: UiVariant.ios);
      expect(ModalRoute.of(tester.element(find.byType(SettingsScreen))), isA<CupertinoPageRoute<void>>());
      expect(find.text('Remote'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(SettingsUiKeys.title)).style!.fontSize, 16);
      await tester.tap(find.byKey(SettingsUiKeys.backButton));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
    });
  });

  group('rows', () {
    testWidgets('every mockup string is present, verbatim', (tester) async {
      await pumpSettings(tester);
      for (final text in [
        'Volume Step Size',
        '0.5 dB',
        '1 dB',
        '2 dB',
        'Startup / Source-Switch Volume',
        'Default volume on startup/ source switch',
        'Volume Floor',
        'Lowest volume possible to set',
        'Volume Ceiling',
        'Highest volume possible to set',
        'Theme',
        'System',
        'Version',
        'View on GitHub',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(textAt(tester, SettingsUiKeys.versionValue), kAppVersion);
      expect(find.text('Restore Defaults'), findsNothing);
      expect(find.byKey(SettingsUiKeys.persistenceNote), findsNothing);
    });

    testWidgets('the segmented step size persists at once', (tester) async {
      final store = await pumpSettings(tester);
      await tester.tap(find.byKey(SettingsUiKeys.stepOption(VolumeStepDb.two)));
      await tester.pump();
      expect(settingsOf(tester).stepDb, VolumeStepDb.two);
      expect(store.values[SettingsKeys.volumeStepDb], 2.0);
    });

    testWidgets('View on GitHub opens the repo URL through the injected opener', (tester) async {
      final opened = <Uri>[];
      await pumpSettings(tester, urlOpener: (uri) async {
        opened.add(uri);
        return true;
      });
      await tester.ensureVisible(find.byKey(SettingsUiKeys.githubRow));
      await tester.tap(find.byKey(SettingsUiKeys.githubRow));
      await tester.pump();
      expect(opened, [Uri.parse(kGitHubUrl)]);
    });

    testWidgets('persistence note: an unavailable store', (tester) async {
      await pumpSettings(tester, storeError: StateError('no platform'));
      expect(find.byKey(SettingsUiKeys.persistenceNote), findsOneWidget);
      expect(find.textContaining("can't be saved on this device"), findsOneWidget);
    });

    testWidgets('persistence note: a failed write', (tester) async {
      await pumpSettings(tester, store: _ThrowingStore());
      expect(find.byKey(SettingsUiKeys.persistenceNote), findsNothing);
      await tester.tap(find.byKey(SettingsUiKeys.stepOption(VolumeStepDb.half)));
      await tester.pump();
      await tester.pump();
      expect(find.textContaining("couldn't be saved"), findsOneWidget);
      expect(settingsOf(tester).stepDb, VolumeStepDb.half, reason: 'the in-memory value is kept');
    });
  });

  group('steppers', () {
    testWidgets('a tap moves exactly 1 dB, persists, and renders −41 dB with the thin space', (tester) async {
      final store = await pumpSettings(tester);
      expect(stepperText(tester, SettingsUiKeys.startupStepper), '−40 dB');
      await tester.tap(find.byKey(SettingsUiKeys.startupStepper.minus));
      await tester.pump();
      expect(stepperText(tester, SettingsUiKeys.startupStepper), '−41 dB');
      expect(store.values[SettingsKeys.startupVolumeDb], -41.0);
    });

    testWidgets('hold-to-repeat: first step on press, first repeat at 560 ms, then 128, 116 … ms', (tester) async {
      await pumpSettings(tester);
      final gesture = await holdStepper(tester, SettingsUiKeys.startupStepper.plus);
      expect(settingsOf(tester).startupVolumeDb, -39.0, reason: 'one step on press');
      await tester.pump(const Duration(milliseconds: 559));
      expect(settingsOf(tester).startupVolumeDb, -39.0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(settingsOf(tester).startupVolumeDb, -38.0);
      await tester.pump(const Duration(milliseconds: 128));
      expect(settingsOf(tester).startupVolumeDb, -37.0);
      await tester.pump(const Duration(milliseconds: 116));
      expect(settingsOf(tester).startupVolumeDb, -36.0);
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(settingsOf(tester).startupVolumeDb, -36.0, reason: 'stops on release');
    });

    testWidgets("at the 1 dB gap the floor's + is dimmed to 0.4 and refuses; the ceiling's − likewise", (tester) async {
      final store = await pumpSettings(
        tester,
        initialSettings: AppSettings.defaults.copyWith(floorDb: -20, ceilingDb: -19),
      );
      expect(blockedOpacity(tester, SettingsUiKeys.floorStepper.plus), 0.4);
      expect(blockedOpacity(tester, SettingsUiKeys.floorStepper.minus), 1.0);
      expect(blockedOpacity(tester, SettingsUiKeys.ceilingStepper.minus), 0.4);
      expect(blockedOpacity(tester, SettingsUiKeys.ceilingStepper.plus), 1.0);
      await tester.tap(find.byKey(SettingsUiKeys.floorStepper.plus), warnIfMissed: false);
      await tester.pump();
      expect(settingsOf(tester).floorDb, -20.0, reason: 'the bound refuses');
      expect(store.writeLog, isEmpty);
      // Only the pressed value moves: lowering the floor frees the ceiling's −.
      await tester.tap(find.byKey(SettingsUiKeys.floorStepper.minus));
      await tester.pump();
      expect(settingsOf(tester).floorDb, -21.0);
      expect(settingsOf(tester).ceilingDb, -19.0);
      expect(blockedOpacity(tester, SettingsUiKeys.ceilingStepper.minus), 1.0);
    });

    testWidgets('the range ends dim too: −96 blocks −, 0 blocks +', (tester) async {
      await pumpSettings(tester, initialSettings: AppSettings.defaults.copyWith(floorDb: -96, ceilingDb: 0, startupVolumeDb: 0));
      expect(blockedOpacity(tester, SettingsUiKeys.floorStepper.minus), 0.4);
      expect(blockedOpacity(tester, SettingsUiKeys.ceilingStepper.plus), 0.4);
      expect(blockedOpacity(tester, SettingsUiKeys.startupStepper.plus), 0.4);
    });

    testWidgets('tap-to-type: magnitude only, clamped, empty and Escape revert', (tester) async {
      final store = await pumpSettings(tester);
      final keys = SettingsUiKeys.startupStepper;
      await tester.tap(find.byKey(keys.value));
      await tester.pump();
      expect(find.byKey(keys.entry), findsOneWidget);
      await tester.enterText(find.byKey(keys.entry), '35');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(find.byKey(keys.entry), findsNothing);
      expect(stepperText(tester, keys), '−35 dB');
      expect(store.values[SettingsKeys.startupVolumeDb], -35.0);

      await tester.tap(find.byKey(keys.value));
      await tester.pump();
      await tester.enterText(find.byKey(keys.entry), '100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(settingsOf(tester).startupVolumeDb, -96.0, reason: 'clamped to the bound');

      await tester.tap(find.byKey(keys.value));
      await tester.pump();
      await tester.enterText(find.byKey(keys.entry), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(settingsOf(tester).startupVolumeDb, -96.0, reason: 'empty keeps the previous value');

      await tester.tap(find.byKey(keys.value));
      await tester.pump();
      await tester.enterText(find.byKey(keys.entry), '20');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(keys.entry), findsNothing);
      expect(settingsOf(tester).startupVolumeDb, -96.0, reason: 'Escape reverts');
    });
  });

  group('theme', () {
    for (final variant in UiVariant.values) {
      testWidgets('${variant.name}: choosing Light persists, closes the sheet after 180 ms and flips the tokens', (tester) async {
        tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        final store = await pumpSettings(tester, variant: variant);
        expect(AppTheme.of(tester.element(find.byType(SettingsScreen))).tokens, AppTokens.dark);
        await tester.tap(find.byKey(SettingsUiKeys.themeRow));
        await tester.pumpAndSettle();
        expect(find.text('Choose Theme'), findsOneWidget);
        await tester.tap(find.byKey(SettingsUiKeys.themeOption(AppThemeMode.light)));
        await tester.pump();
        expect(store.values[SettingsKeys.themeMode], 'light');
        expect(find.text('Choose Theme'), findsOneWidget, reason: 'closes after the delay, not at once');
        await tester.pump(const Duration(milliseconds: 180));
        await tester.pumpAndSettle();
        expect(find.text('Choose Theme'), findsNothing);
        expect(textAt(tester, SettingsUiKeys.themeTrailing), 'Light');
        expect(AppTheme.of(tester.element(find.byType(SettingsScreen))).tokens, AppTokens.light);
      });
    }
  });

  testWidgets('a ceiling change in Settings reaches the Control dial after popping (checklist 11)', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.byKey(SettingsUiKeys.ceilingStepper.minus));
    await tester.pump();
    expect(settingsOf(tester).ceilingDb, -11.0);
    await tester.tap(find.byKey(SettingsUiKeys.backButton));
    await tester.pumpAndSettle();
    expect(readState(tester).ceilingDb, -11.0);
    expect(find.byKey(ControlKeys.dial), findsOneWidget);
  });
}
