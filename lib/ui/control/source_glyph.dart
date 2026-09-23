import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'source_glyphs.dart';

/// A source's glyph as the mockups render it: the Unicode symbol from
/// [sourceGlyphFor], or a painted half-filled ring for Spotify (the ◐
/// character is far smaller than its siblings in most fonts). Flat
/// `copperBright` in dark; in light the gold radial gradient clipped to
/// the glyph plus its soft drop shadow (`.phone.light .source-icon`).
class SourceGlyph extends StatelessWidget {
  const SourceGlyph({super.key, required this.name, required this.size});

  /// The live source name; `null` renders the "–" placeholder.
  final String? name;

  /// The CSS font size of the chip (16 in the trigger, 15 in the sheet).
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    final gold = t.glyphGoldColors;
    final spotify = isSpotifySource(name);

    Widget glyph(Color color, {Color? shadow}) => spotify
        ? CustomPaint(
            size: Size.square(size * 1.05),
            painter: _SpotifyGlyphPainter(color: color, shadow: shadow),
          )
        : Text(
            sourceGlyphFor(name),
            style: TextStyle(
              fontSize: size,
              color: color,
              height: 1,
              shadows: shadow == null ? null : [Shadow(color: shadow, offset: const Offset(0, 3), blurRadius: 5)],
            ),
          );

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
            center: AppTokens.glyphGoldCenter,
            radius: 0.75,
            colors: gold,
            stops: AppTokens.glyphGoldStops,
          ).createShader(Offset.zero & bounds.size),
          child: glyph(const Color(0xFFFFFFFF)),
        ),
      ],
    );
  }
}

/// `<circle r=7.6 stroke-width=1.6/>` + the left half filled
/// (`M10 2.4 A7.6 7.6 0 0 0 10 17.6 Z`) in a 20-unit viewBox.
class _SpotifyGlyphPainter extends CustomPainter {
  const _SpotifyGlyphPainter({required this.color, this.shadow});

  final Color color;
  final Color? shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 20;
    canvas.scale(scale, scale);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color;
    final half = Path()
      ..moveTo(10, 2.4)
      ..arcToPoint(const Offset(10, 17.6), radius: const Radius.circular(7.6), clockwise: false)
      ..close();
    final shadowColor = shadow;
    if (shadowColor != null) {
      final blur = Paint()
        ..color = shadowColor
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      canvas.save();
      canvas.translate(0, 3 / scale);
      canvas.drawCircle(const Offset(10, 10), 7.6, blur..style = PaintingStyle.stroke..strokeWidth = 1.6);
      canvas.drawPath(half, blur..style = PaintingStyle.fill);
      canvas.restore();
    }
    canvas.drawCircle(const Offset(10, 10), 7.6, ring);
    canvas.drawPath(half, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SpotifyGlyphPainter old) => old.color != color || old.shadow != shadow;
}
