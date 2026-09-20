import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/ui_variant.dart';
import '../config/window_class.dart';
import '../domain/settings/app_settings.dart';
import '../domain/settings/settings_owner.dart';
import 'control/control_screen.dart';
import 'platform/platform_style.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';
import 'theme/app_typography.dart';

/// Root widget. Picks the Material or Cupertino shell from
/// [uiVariantProvider] and installs, inside each shell's `builder:`
/// (below the app's `MediaQuery`, above its `Navigator`):
///
/// - [WindowClassScope] — width/height class, rebuilt on every resize
///   (TODO 2.0.0 / 2.0.1);
/// - [AppTheme] — tokens for the current OS brightness, typography for the
///   variant, per-variant style numbers (TODO 2.0.11).
///
/// Brightness comes from the persisted Theme setting: `system` follows
/// the OS, `dark` / `light` force it. The override lives in [wrap] alone —
/// the `MediaQuery` there makes Cupertino follow it, the tokens are
/// derived from it, and `MaterialApp.themeMode` mirrors it because
/// Material resolves its `ThemeData` above `builder`.
class DevialetRemoteApp extends ConsumerWidget {
  const DevialetRemoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(uiVariantProvider);
    final style = ref.watch(platformStyleProvider);
    final type = AppTypography.forVariant(variant);
    // `select`: a dB tick in Settings must not rebuild the app shells.
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));

    Widget wrap(BuildContext ctx, Widget? child) {
      final brightness = switch (themeMode) {
        AppThemeMode.system => MediaQuery.platformBrightnessOf(ctx),
        AppThemeMode.dark => Brightness.dark,
        AppThemeMode.light => Brightness.light,
      };
      return MediaQuery(
        data: MediaQuery.of(ctx).copyWith(platformBrightness: brightness),
        child: WindowClassScope(
          value: WindowClass.fromSize(MediaQuery.sizeOf(ctx)),
          child: AppTheme(tokens: AppTokens.forBrightness(brightness), type: type, style: style, child: child!),
        ),
      );
    }

    const home = ControlScreen();
    if (variant == UiVariant.ios) {
      return CupertinoApp(
        debugShowCheckedModeBanner: false,
        theme: buildCupertinoTheme(type),
        builder: wrap,
        home: home,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildMaterialTheme(AppTokens.light, type),
      darkTheme: buildMaterialTheme(AppTokens.dark, type),
      themeMode: switch (themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.light => ThemeMode.light,
      },
      builder: wrap,
      home: home,
    );
  }
}
