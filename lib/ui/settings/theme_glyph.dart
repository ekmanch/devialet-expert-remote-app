import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/settings/app_settings.dart';
import '../theme/app_tokens.dart';
import '../widgets/painted_glyph.dart';

/// The theme sheet's row glyph, painted through [PaintedGlyph] in the
/// same 20-unit box as the source glyphs (the mockup's ◐ ☾ ☀ come out
/// of the phone's font tiny — 2026-09-23 S25).
class ThemeGlyph extends StatelessWidget {
  const ThemeGlyph({super.key, required this.mode, required this.size});

  final AppThemeMode mode;

  /// The CSS font size of the chip (15 in the sheet).
  final double size;

  /// The sun's rays all shade alike only if the gold radiates from the
  /// disc: centred, and reaching the ray tips (7.6 of the 20-unit box
  /// ≈ 0.38 of the side) well inside the gradient's darkest stop.
  static const Alignment sunGradientCenter = Alignment.center;
  static const double sunGradientRadius = 0.5;

  @override
  Widget build(BuildContext context) => PaintedGlyph(
    size: size,
    gradientCenter: mode == AppThemeMode.light ? sunGradientCenter : AppTokens.glyphGoldCenter,
    gradientRadius: mode == AppThemeMode.light ? sunGradientRadius : 0.75,
    painter: (color, shadow) => ThemeGlyphPainter(mode: mode, color: color, shadow: shadow),
  );
}

/// - system ◐: the 7.6-radius ring, left half filled
/// - dark ☾: a crescent — the ring's left half minus a circle offset right
/// - light ☀: a filled 3.2-radius disc with eight 1.6 rays out to 7.6
class ThemeGlyphPainter extends GlyphPainter {
  const ThemeGlyphPainter({required this.mode, required super.color, super.shadow});

  final AppThemeMode mode;

  static const _c = GlyphPainter.centre;
  static const _r = GlyphPainter.radius;

  @override
  void draw(Canvas canvas, Color color, MaskFilter? mask) {
    final stroke = GlyphPainter.strokePaint(color, mask);
    final fill = GlyphPainter.fillPaint(color, mask);

    switch (mode) {
      case AppThemeMode.system:
        canvas.drawCircle(_c, _r, stroke);
        canvas.drawPath(GlyphPainter.leftHalf(), fill);
      case AppThemeMode.dark:
        // Outer edge: the ring's left half, top to bottom. Inner edge:
        // back up along a circle centred 4 units right of the box centre
        // through the same two tips (radius √(4² + 7.6²) ≈ 8.59), leaving
        // a crescent 3 units thick at its waist.
        final inner = math.sqrt(4 * 4 + _r * _r);
        final crescent = Path()
          ..moveTo(_c.dx, _c.dy - _r)
          ..arcToPoint(Offset(_c.dx, _c.dy + _r), radius: const Radius.circular(_r), clockwise: false)
          ..arcToPoint(Offset(_c.dx, _c.dy - _r), radius: Radius.circular(inner), clockwise: true)
          ..close();
        canvas.drawPath(crescent, fill);
        canvas.drawPath(crescent, GlyphPainter.strokePaint(color, mask, width: 1.0));
      case AppThemeMode.light:
        canvas.drawCircle(_c, 3.2, fill);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          final dir = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(_c + dir * 5.4, _c + dir * _r, stroke);
        }
    }
  }

  @override
  bool shouldRepaint(covariant ThemeGlyphPainter old) => old.mode != mode || super.shouldRepaint(old);
}
