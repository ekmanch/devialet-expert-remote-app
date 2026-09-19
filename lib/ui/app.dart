import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/ui_variant.dart';
import '../config/window_class.dart';
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
/// Brightness follows the OS here; Task 3.4.x's Theme setting plugs into
/// [_wrap] and nowhere else.
class DevialetRemoteApp extends ConsumerWidget {
  const DevialetRemoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(uiVariantProvider);
    final style = ref.watch(platformStyleProvider);
    final type = AppTypography.forVariant(variant);

    Widget wrap(BuildContext ctx, Widget? child) {
      final tokens = AppTokens.forBrightness(MediaQuery.platformBrightnessOf(ctx));
      return WindowClassScope(
        value: WindowClass.fromSize(MediaQuery.sizeOf(ctx)),
        child: AppTheme(tokens: tokens, type: type, style: style, child: child!),
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
      themeMode: ThemeMode.system,
      builder: wrap,
      home: home,
    );
  }
}
