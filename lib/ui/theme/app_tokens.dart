import 'package:flutter/material.dart';

/// Colour / gradient / shadow tokens lifted 1:1 from the mockups' CSS (v36;
/// v39 changed no variables, only the light dB-readout gradient)
/// variables (`:root` = dark, `.phone.light` = light). One place, so Task
/// 3.4.x's Theme setting and Task 5.0.0's icon reuse them (TODO 2.0.11).
///
/// Registered as a [ThemeExtension] so Material widgets can reach it via
/// `Theme.of(context).extension<AppTokens>()`, but the canonical accessor
/// is `AppTheme.of(context).tokens`, which works under Cupertino too.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.copper,
    required this.copperBright,
    required this.copperDim,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.divider,
    required this.danger,
    required this.success,
    required this.successBright,
    required this.warning,
    required this.warningBright,
    required this.dialTrack,
    required this.cardShadow,
    required this.dialGradientColors,
    required this.dialGradientStops,
    required this.sheetBg1,
    required this.sheetBg2,
    required this.sheetTint,
    required this.scrimMaterial,
    required this.scrimCupertino,
    required this.dotGlow,
    required this.wordmarkGradientColors,
    required this.settingsHeadingGradientColors,
    required this.glyphGoldColors,
    required this.dialValueGradientColors,
    required this.listenArc,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color copper;
  /// The accent (`--copper-bright`); `--accent-rgb` is this colour's RGB.
  final Color copperBright;
  final Color copperDim;
  final Color text;
  final Color textDim;
  final Color textFaint;
  final Color divider;
  final Color danger;
  final Color success;
  final Color successBright;
  final Color warning;
  final Color warningBright;
  final Color dialTrack;
  final List<BoxShadow> cardShadow;
  /// Dial arc gradient: dark = 2-stop copper, light = 5-stop gold "shine".
  final List<Color> dialGradientColors;
  final List<double>? dialGradientStops;
  final Color sheetBg1;
  final Color sheetBg2;
  /// iOS frosted-sheet tint (behind a 28px blur).
  final Color sheetTint;
  final Color scrimMaterial;
  final Color scrimCupertino;
  /// Device-dot glow for the connected state (`0 0 8px 2px rgba(accent,.55)`);
  /// transparent in light, where the dot is a radial gradient instead.
  final Color dotGlow;

  /// Foil-text sheen on the "DEVIALET" wordmark / eyebrow, **light theme
  /// only** (both v19 mockups: `linear-gradient(90deg, #a8710b, #d99a1f,
  /// #fbe6ab)` clipped to the letterforms — dark on the left, bright on
  /// the right, like foil-stamped print). `null` = flat `copperBright`
  /// (dark theme). The dB readout has its own, narrower gradient — see
  /// [dialValueGradientColors].
  final List<Color>? wordmarkGradientColors;

  /// Settings-screen section headings (v28/v29/v32): the accent moved off
  /// the numbers onto the headings. Light = a gradient like the wordmark
  /// but ending in a deeper gold so 11px caps stay legible on white
  /// (`#a8710b → #d99a1f (55 %) → #efc36a`); `null` = flat [copperBright]
  /// (dark: "flat copper + glow; gradients are light-only").
  final List<Color>? settingsHeadingGradientColors;
  static const List<double> settingsHeadingGradientStops = [0.0, 0.55, 1.0];

  /// Light theme source glyphs (`.phone.light .source-icon`): the gold
  /// radial gradient clipped to the glyph, `circle at 32% 28%`,
  /// `#fcecc0 → #f0a623 (38 %) → #a8710b` — the same three stops as the
  /// connected device dot. `null` = flat [copperBright] (dark).
  final List<Color>? glyphGoldColors;

  /// Light theme dB readout (`.phone.light .dial-value`): a two-stop
  /// left→right gold clipped to the digits. v36 used `#c17f0e → #f0c873`
  /// (never ported — the readout stayed flat `copperBright`); v39
  /// brightened it to `#dca136 → #f3cf7c` ("Light-theme dB readout:
  /// brighter gold") and that is what ships. Only two stops, same hue
  /// family: over 4–5 characters a wider range showed as two colour
  /// blocks instead of a sweep. `null` = flat [copperBright] (dark keeps
  /// its glow instead).
  final List<Color>? dialValueGradientColors;
  static const List<double> glyphGoldStops = [0.0, 0.38, 1.0];
  static const Alignment glyphGoldCenter = Alignment(-0.36, -0.44);
  /// `text-shadow: 0 3px 5px rgba(160,110,10,.35)` under a gold glyph.
  static const Color glyphGoldShadow = Color(0x59A06E0A);

  /// The amp picker's "listening" arcs (`.listen-arcs .la`): a muted
  /// copper in dark (`#a06f4a`), the accent in light.
  final Color listenArc;

  /// Bare header icon buttons' press feedback (v36): a neutral
  /// `rgba(127,127,127,.16)` disc, the same in both themes.
  static const Color iconPressHighlight = Color(0x297F7F7F);

  /// `rgba(var(--accent-rgb), alpha)` in the CSS.
  Color accentTint(double alpha) => copperBright.withValues(alpha: alpha);

  bool get isDark => brightness == Brightness.dark;

  static const AppTokens dark = AppTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF0E0E10),
    surface: Color(0xFF121214),
    surface2: Color(0xFF161618),
    surface3: Color(0xFF141416),
    copper: Color(0xFFC17F4E),
    copperBright: Color(0xFFE3A06A),
    copperDim: Color(0xFF8A5C39),
    text: Color(0xFFF2F0EC),
    textDim: Color(0xFF9A9A9F),
    textFaint: Color(0xFF5C5C60),
    divider: Color(0x1AFFFFFF),
    danger: Color(0xFFB5544A),
    success: Color(0xFF5FA374),
    successBright: Color(0xFF7BC796),
    warning: Color(0xFFA3813A),
    warningBright: Color(0xFFE0B563),
    dialTrack: Color(0xFF232326),
    cardShadow: <BoxShadow>[],
    dialGradientColors: [Color(0xFF8A5C39), Color(0xFFE3A06A)],
    dialGradientStops: null,
    sheetBg1: Color(0xFF141416),
    sheetBg2: Color(0xFF101012),
    sheetTint: Color(0xC717171A),
    scrimMaterial: Color(0x8C000000),
    scrimCupertino: Color(0x6B08080A),
    dotGlow: Color(0x8CE3A06A),
    wordmarkGradientColors: null,
    settingsHeadingGradientColors: null,
    glyphGoldColors: null,
    dialValueGradientColors: null,
    listenArc: Color(0xFFA06F4A),
  );

  static const AppTokens light = AppTokens(
    brightness: Brightness.light,
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFFFFFFF),
    surface3: Color(0xFFFFFFFF),
    copper: Color(0xFFC17F4E),
    // v36: `#c79a2e` (was `#d98c0f`), and `--accent-rgb` with it.
    copperBright: Color(0xFFC79A2E),
    copperDim: Color(0xFFDDBB6E),
    text: Color(0xFF18140F),
    textDim: Color(0xFF6F6A61),
    textFaint: Color(0xFFA39C8F),
    divider: Color(0x1A18140F),
    danger: Color(0xFFB5544A),
    success: Color(0xFF5FA374),
    successBright: Color(0xFF7BC796),
    warning: Color(0xFFA3813A),
    warningBright: Color(0xFFE0B563),
    dialTrack: Color(0xFFE4E0D6),
    cardShadow: [
      BoxShadow(color: Color(0x1A18140F), offset: Offset(0, 3), blurRadius: 10, spreadRadius: -3),
      BoxShadow(color: Color(0x0F18140F), offset: Offset(0, 1), blurRadius: 3),
    ],
    dialGradientColors: [
      Color(0xFF9C6A0C),
      Color(0xFFF6D98A),
      Color(0xFFE29A1A),
      Color(0xFFFBE6AB),
      Color(0xFFA8710B),
    ],
    dialGradientStops: [0.0, 0.22, 0.45, 0.68, 1.0],
    sheetBg1: Color(0xFFFFFFFF),
    sheetBg2: Color(0xFFFFFFFF),
    sheetTint: Color(0xF5FFFFFF),
    scrimMaterial: Color(0x8C000000),
    scrimCupertino: Color(0x6B08080A),
    dotGlow: Color(0x00000000),
    wordmarkGradientColors: [Color(0xFFA8710B), Color(0xFFD99A1F), Color(0xFFFBE6AB)],
    settingsHeadingGradientColors: [Color(0xFFA8710B), Color(0xFFD99A1F), Color(0xFFEFC36A)],
    glyphGoldColors: [Color(0xFFFCECC0), Color(0xFFF0A623), Color(0xFFA8710B)],
    dialValueGradientColors: [Color(0xFFDCA136), Color(0xFFF3CF7C)],
    listenArc: Color(0xFFC79A2E),
  );

  static AppTokens forBrightness(Brightness b) => b == Brightness.dark ? dark : light;

  @override
  AppTokens copyWith() => this;

  /// Tokens are two fixed palettes; theme changes snap rather than tween.
  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) =>
      other is AppTokens && t >= 0.5 ? other : this;
}
