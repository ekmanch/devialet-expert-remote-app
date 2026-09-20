import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/ui/control/control_screen.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_theme.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_tokens.dart';

import 'support/pump_control.dart';

void main() {
  for (final variant in UiVariant.values) {
    testWidgets('${variant.name}: the Light setting renders light tokens under a dark OS', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        hermeticApp(variant: variant, initialSettings: AppSettings.defaults.copyWith(themeMode: AppThemeMode.light)),
      );
      await tester.pump();
      final context = tester.element(find.byType(ControlScreen));
      expect(AppTheme.of(context).tokens, AppTokens.light);
      expect(MediaQuery.platformBrightnessOf(context), Brightness.light, reason: 'Cupertino follows the override');
      if (variant == UiVariant.android) expect(Theme.of(context).brightness, Brightness.light);
      if (variant == UiVariant.ios) expect(CupertinoTheme.brightnessOf(context), Brightness.light);
    });

    testWidgets('${variant.name}: proof the override is what flips it — System under a dark OS renders dark', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(hermeticApp(variant: variant, initialSettings: AppSettings.defaults));
      await tester.pump();
      final context = tester.element(find.byType(ControlScreen));
      expect(AppTheme.of(context).tokens, AppTokens.dark);
    });
  }
}
