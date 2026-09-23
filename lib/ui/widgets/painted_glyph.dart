import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// Builds the painter for one glyph copy: [color] is what to paint;
/// [shadow], when set, asks for a blurred copy 3 CSS px lower first.
typedef GlyphPainterBuilder = CustomPainter Function(Color color, Color? shadow);

/// A painted list-row glyph (`.source-icon` in the mockups): a vector in
/// a box of `size * 1.05` — the size the v36 mockup's Spotify SVG renders
/// at — so glyphs match regardless of the phone's font. Flat
/// `copperBright` in dark; in light the gold radial gradient clipped to
/// the glyph plus its soft drop shadow (`.phone.light .source-icon`).
class PaintedGlyph extends StatelessWidget {
  const PaintedGlyph({
    super.key,
    required this.size,
    required this.painter,
    this.gradientCenter = AppTokens.glyphGoldCenter,
    this.gradientRadius = 0.75,
    this.opticalScale = 1.0,
  });

  /// The CSS font size of the chip (16 in the trigger, 15 in the sheets).
  final double size;
  final GlyphPainterBuilder painter;

  /// Where the light theme's gold radial gradient is brightest. The
  /// mockup's `circle at 32% 28%` by default; a glyph that radiates from
  /// its middle (the sun) centres it so every ray shades the same way.
  final Alignment gradientCenter;
  final double gradientRadius;

  /// Optical sizing: an outlined, detailed shape reads lighter than a
  /// filled disc drawn in the same box, so such a glyph may be drawn a
  /// little larger than the box's nominal `size * 1.05`. Measured on the
  /// S25, not guessed — see `ManualEntryGlyph`.
  final double opticalScale;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    final gold = t.glyphGoldColors;

    Widget glyph(Color color, {Color? shadow}) =>
        CustomPaint(size: Size.square(size * 1.05 * opticalScale), painter: painter(color, shadow));

    if (gold == null) return glyph(t.copperBright);

    // The shadow is a separate, unmasked copy underneath: `ShaderMask`
    // would tint the shadow gold too.
    return Stack(
      alignment: Alignment.center,
      children: [
        glyph(const Color(0x00000000), shadow: AppTokens.glyphGoldShadow),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => RadialGradient(
            center: gradientCenter,
            radius: gradientRadius,
            colors: gold,
            stops: AppTokens.glyphGoldStops,
          ).createShader(Offset.zero & bounds.size),
          child: glyph(const Color(0xFFFFFFFF)),
        ),
      ],
    );
  }
}

/// Base for glyph painters sharing the 20-unit box: scales the canvas,
/// paints the optional blurred shadow copy, then the glyph itself.
/// Subclasses draw with [draw] using the given paints.
abstract class GlyphPainter extends CustomPainter {
  const GlyphPainter({required this.color, this.shadow});

  final Color color;
  final Color? shadow;

  /// The box centre and the ring radius the v36 Spotify SVG used
  /// (`<circle r=7.6 stroke-width=1.6/>` in a 20-unit viewBox).
  static const Offset centre = Offset(10, 10);
  static const double radius = 7.6;
  static const double strokeWidth = 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 20;
    canvas.scale(scale, scale);
    final shadowColor = shadow;
    if (shadowColor != null) {
      canvas.save();
      canvas.translate(0, 3 / scale);
      draw(canvas, shadowColor, const MaskFilter.blur(BlurStyle.normal, 2.5));
      canvas.restore();
    }
    draw(canvas, color, null);
  }

  void draw(Canvas canvas, Color color, MaskFilter? mask);

  static Paint strokePaint(Color color, MaskFilter? mask, {double width = strokeWidth}) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color
    ..maskFilter = mask;

  static Paint fillPaint(Color color, MaskFilter? mask) => Paint()
    ..color = color
    ..maskFilter = mask;

  /// The left half of the ring, filled (`M10 2.4 A7.6 7.6 0 0 0 10 17.6 Z`).
  static Path leftHalf() => Path()
    ..moveTo(centre.dx, centre.dy - radius)
    ..arcToPoint(Offset(centre.dx, centre.dy + radius), radius: const Radius.circular(radius), clockwise: false)
    ..close();

  @override
  bool shouldRepaint(covariant GlyphPainter old) => old.color != color || old.shadow != shadow;
}
