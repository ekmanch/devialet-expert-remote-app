import 'package:flutter/widgets.dart';

import '../widgets/painted_glyph.dart';

/// The amp picker's "Enter IP Manually" glyph: a keyboard painted through
/// [PaintedGlyph], so it shares the source glyphs' box, their copper in
/// dark and their gold gradient + shadow in light (owner pick, option A
/// of the 2026-09-23 preview). Replaces the ⌨ character, which Samsung
/// rendered as a colour emoji, and the bordered chip the mockup never
/// declared.
class ManualEntryGlyph extends StatelessWidget {
  const ManualEntryGlyph({super.key, required this.size});

  /// The CSS font size of the chip (15 in the sheet).
  final double size;

  /// Optical sizing, measured on the S25 (2026-09-23): in the nominal box
  /// the slab painted 40 × 30 px against the amp dot's 40 × 40, half the
  /// dot's ink, and read smaller. At 1.15 (slab 11.2 of the 20 units) it
  /// painted 46 × 36 and read level; the owner's updated mockup then
  /// nudged it a touch past the dot, so 1.25 (≈ 50 × 39 px). The row's
  /// leading slot is 20 dp; the box is 15 · 1.05 · 1.25 ≈ 19.7.
  static const double opticalScale = 1.25;

  @override
  Widget build(BuildContext context) => PaintedGlyph(
    size: size,
    opticalScale: opticalScale,
    painter: (color, shadow) => ManualEntryGlyphPainter(color: color, shadow: shadow),
  );
}

/// A rounded slab spanning the ring's width (2.4..17.6) and most of its
/// height (4.4..15.6), one row of four key ticks and a space bar, all
/// 1.6 round-capped strokes.
class ManualEntryGlyphPainter extends GlyphPainter {
  const ManualEntryGlyphPainter({required super.color, super.shadow});

  @override
  void draw(Canvas canvas, Color color, MaskFilter? mask) {
    final stroke = GlyphPainter.strokePaint(color, mask);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(2.4, 4.4, 15.2, 11.2), const Radius.circular(2)),
      stroke,
    );
    for (final x in const [5.8, 8.6, 11.4, 14.2]) {
      canvas.drawLine(Offset(x, 8.0), Offset(x, 8.0), stroke); // round-capped dot
    }
    canvas.drawLine(const Offset(7.2, 12.0), const Offset(12.8, 12.0), stroke);
  }
}
