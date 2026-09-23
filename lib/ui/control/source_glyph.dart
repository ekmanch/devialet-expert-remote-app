import 'package:flutter/widgets.dart';

import '../widgets/painted_glyph.dart';
import 'source_glyphs.dart';

/// A source's glyph, painted (see [SourceGlyphKind]) through
/// [PaintedGlyph], so all six share one size and the light theme's gold.
class SourceGlyph extends StatelessWidget {
  const SourceGlyph({super.key, required this.name, required this.size});

  /// The live source name; `null` renders the "–" placeholder.
  final String? name;

  /// The CSS font size of the chip (16 in the trigger, 15 in the sheet).
  final double size;

  @override
  Widget build(BuildContext context) {
    final kind = sourceGlyphKindFor(name);
    return PaintedGlyph(
      size: size,
      painter: (color, shadow) => SourceGlyphPainter(kind: kind, color: color, shadow: shadow),
    );
  }
}

/// Paints one [SourceGlyphKind] in the shared 20-unit box: a 7.6-radius
/// ring (or a 15.2-wide square / diamond) with a 1.6 stroke.
///
/// - optical ◉: ring + filled centre dot
/// - upnp ◫: square + vertical bisector
/// - roon ◍: ring + vertical hatching
/// - airplay ◈: diamond + filled inner diamond
/// - spotify ◐: ring + left half filled
/// - air ◇: diamond
/// - none –: short horizontal dash
class SourceGlyphPainter extends GlyphPainter {
  const SourceGlyphPainter({required this.kind, required super.color, super.shadow});

  final SourceGlyphKind kind;

  static const _c = GlyphPainter.centre;
  static const _r = GlyphPainter.radius;

  @override
  void draw(Canvas canvas, Color color, MaskFilter? mask) {
    final stroke = GlyphPainter.strokePaint(color, mask);
    final fill = GlyphPainter.fillPaint(color, mask);

    switch (kind) {
      case SourceGlyphKind.optical:
        canvas.drawCircle(_c, _r, stroke);
        canvas.drawCircle(_c, 3.4, fill);
      case SourceGlyphKind.upnp:
        final box = RRect.fromRectAndRadius(Rect.fromCircle(center: _c, radius: _r), const Radius.circular(1.6));
        canvas.drawRRect(box, stroke);
        canvas.drawLine(const Offset(10, 2.4), const Offset(10, 17.6), stroke);
      case SourceGlyphKind.roon:
        canvas.drawCircle(_c, _r, stroke);
        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromCircle(center: _c, radius: _r - 1.6)));
        final hatch = GlyphPainter.strokePaint(color, mask, width: 1.2)..strokeCap = StrokeCap.butt;
        for (final x in const [5.2, 7.6, 10.0, 12.4, 14.8]) {
          canvas.drawLine(Offset(x, 2), Offset(x, 18), hatch);
        }
        canvas.restore();
      case SourceGlyphKind.airplay:
        canvas.drawPath(_diamond(_r), stroke);
        canvas.drawPath(_diamond(3.4), fill);
      case SourceGlyphKind.spotify:
        canvas.drawCircle(_c, _r, stroke);
        canvas.drawPath(GlyphPainter.leftHalf(), fill);
      case SourceGlyphKind.air:
        canvas.drawPath(_diamond(_r), stroke);
      case SourceGlyphKind.none:
        canvas.drawLine(const Offset(5.5, 10), const Offset(14.5, 10), stroke);
    }
  }

  static Path _diamond(double r) => Path()
    ..moveTo(_c.dx, _c.dy - r)
    ..lineTo(_c.dx + r, _c.dy)
    ..lineTo(_c.dx, _c.dy + r)
    ..lineTo(_c.dx - r, _c.dy)
    ..close();

  @override
  bool shouldRepaint(covariant SourceGlyphPainter old) => old.kind != kind || super.shouldRepaint(old);
}
