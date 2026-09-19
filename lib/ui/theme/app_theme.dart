import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../platform/platform_style.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// The one accessor shared widgets use for colours, type and per-variant
/// numbers. Installed by `DevialetRemoteApp` inside the app's `builder:`.
/// Every text colour must come from [tokens] — the mockups' light theme
/// once shipped ghost text because a colour was inherited from the wrong
/// scope; don't rely on `DefaultTextStyle`.
class AppTheme extends InheritedWidget {
  const AppTheme({
    super.key,
    required this.tokens,
    required this.type,
    required this.style,
    required super.child,
  });

  final AppTokens tokens;
  final AppTypography type;
  final PlatformStyle style;

  static AppTheme of(BuildContext context) {
    final theme = context.dependOnInheritedWidgetOfExactType<AppTheme>();
    assert(theme != null, 'No AppTheme above this context');
    return theme!;
  }

  @override
  bool updateShouldNotify(AppTheme oldWidget) =>
      tokens != oldWidget.tokens || type != oldWidget.type || style != oldWidget.style;
}

ThemeData buildMaterialTheme(AppTokens t, AppTypography type) {
  final scheme = ColorScheme.fromSeed(
    seedColor: t.copper,
    brightness: t.brightness,
    surface: t.bg,
    primary: t.copperBright,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: t.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    fontFamily: type.bodyFamily,
    splashColor: t.accentTint(0.10),
    highlightColor: t.accentTint(0.06),
    extensions: [t],
  );
}

CupertinoThemeData buildCupertinoTheme(AppTypography type) {
  const dark = AppTokens.dark;
  const light = AppTokens.light;
  return CupertinoThemeData(
    primaryColor: const CupertinoDynamicColor.withBrightness(
      color: Color(0xFFD98C0F),
      darkColor: Color(0xFFE3A06A),
    ),
    scaffoldBackgroundColor: CupertinoDynamicColor.withBrightness(
      color: light.bg,
      darkColor: dark.bg,
    ),
    barBackgroundColor: CupertinoDynamicColor.withBrightness(
      color: light.surface,
      darkColor: dark.surface,
    ),
    textTheme: type.bodyFamily == null
        ? null
        : CupertinoTextThemeData(textStyle: TextStyle(fontFamily: type.bodyFamily)),
  );
}
