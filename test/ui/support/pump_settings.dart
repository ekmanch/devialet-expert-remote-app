import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_owner.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_store.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/settings/db_stepper.dart';
import 'package:devialet_expert_remote_app/ui/settings/url_opener.dart';

import 'pump_control.dart';

/// Pumps the hermetic app and pushes Settings through the gear.
Future<InMemorySettingsStore> pumpSettings(
  WidgetTester tester, {
  UiVariant variant = UiVariant.android,
  AppSettings? initialSettings,
  InMemorySettingsStore? store,
  Object? storeError,
  UrlOpener? urlOpener,
  Size size = phonePortrait,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final settingsStore = store ?? InMemorySettingsStore();
  await tester.pumpWidget(
    hermeticApp(
      variant: variant,
      settingsStore: settingsStore,
      initialSettings: initialSettings,
      storeError: storeError,
      urlOpener: urlOpener,
    ),
  );
  await tester.pump();
  await tester.tap(find.byKey(ControlKeys.gearButton));
  await tester.pumpAndSettle();
  return settingsStore;
}

AppSettings settingsOf(WidgetTester tester) => containerOf(tester).read(settingsProvider);

/// The value key sits on the pressable; read its `Text`.
String stepperText(WidgetTester tester, DbStepperKeys keys) =>
    tester.widget<Text>(find.descendant(of: find.byKey(keys.value), matching: find.byType(Text))).data!;

/// 1.0 unless the keyed button sits inside a dimming `Opacity`.
double blockedOpacity(WidgetTester tester, Key key) {
  final opacities = find.ancestor(of: find.byKey(key), matching: find.byType(Opacity));
  if (opacities.evaluate().isEmpty) return 1.0;
  return tester.widget<Opacity>(opacities.first).opacity;
}

/// Presses and holds the keyed stepper button; returns the gesture to
/// release. The first step lands once the tap recogniser resolves
/// (kPressTimeout, 100 ms).
Future<TestGesture> holdStepper(WidgetTester tester, Key key) async {
  final gesture = await tester.startGesture(tester.getCenter(find.byKey(key)));
  await tester.pump(const Duration(milliseconds: 100));
  return gesture;
}
