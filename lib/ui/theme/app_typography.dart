import 'package:flutter/widgets.dart';

import '../../config/ui_variant.dart';

/// The three font roles of the mockups. CSS `letter-spacing: 0.22em`
/// becomes `letterSpacing: 0.22 * fontSize`; CSS px map 1:1 to logical px.
@immutable
class AppTypography {
  const AppTypography({required this.bodyFamily});

  /// Inter on Android; `null` (system SF) in the iOS variant — the
  /// mockup's one deliberate platform swap.
  factory AppTypography.forVariant(UiVariant variant) =>
      AppTypography(bodyFamily: variant == UiVariant.android ? interFamily : null);

  static const String displayFamily = 'SpaceGrotesk';
  static const String monoFamily = 'JetBrainsMono';
  static const String interFamily = 'Inter';

  final String? bodyFamily;

  TextStyle display({
    required double size,
    FontWeight weight = FontWeight.w600,
    double letterSpacingEm = 0,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: displayFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacingEm * size,
      color: color,
      height: height,
    );
  }

  TextStyle mono({
    required double size,
    FontWeight weight = FontWeight.w400,
    double letterSpacingEm = 0,
    Color? color,
    double? height,
  }) {
    return TextStyle(
      fontFamily: monoFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacingEm * size,
      color: color,
      height: height,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  TextStyle body({
    required double size,
    FontWeight weight = FontWeight.w400,
    double letterSpacingEm = 0,
    Color? color,
    double? height,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: bodyFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacingEm * size,
      color: color,
      height: height,
      fontStyle: fontStyle,
    );
  }

  @override
  bool operator ==(Object other) => other is AppTypography && other.bodyFamily == bodyFamily;

  @override
  int get hashCode => bodyFamily.hashCode;
}

/// `−25.0` with a real minus sign (U+2212), as every dB value in the
/// mockups. One decimal, always.
String formatDb(double db) {
  final abs = db.abs().toStringAsFixed(1);
  return db < 0 ? '−$abs' : abs;
}
