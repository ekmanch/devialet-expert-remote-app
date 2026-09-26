import 'package:flutter/widgets.dart';

/// The mockups' inline SVGs (24-unit viewBox, `stroke: currentColor`,
/// `fill: none`) as painters, tinted through the framework rather than the
/// asset (checklist item 18). [strokeWidth] is in viewBox units, so it
/// scales with [size] exactly as the SVG's `stroke-width` does (the v36
/// gear and the alternate layout's round-button glyphs are 1.8, the rest 2).
enum StrokeIconKind { gear, speakerMuted, power, minus, plus }

class StrokeIcon extends StatelessWidget {
  const StrokeIcon(this.kind, {super.key, required this.color, this.size = 16, this.strokeWidth = 2});

  final StrokeIconKind kind;
  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _StrokeIconPainter(kind: kind, color: color, strokeWidth: strokeWidth)),
    );
  }
}

class _StrokeIconPainter extends CustomPainter {
  const _StrokeIconPainter({required this.kind, required this.color, required this.strokeWidth});

  final StrokeIconKind kind;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.scale(scale, scale);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (kind) {
      case StrokeIconKind.speakerMuted:
        // alternate v47b: `M11 5 6.5 9H3v6h3.5l4.5 4V5Z` with the cross
        // pulled in to 16–21 so the glyph sits centred in a round button.
        canvas.drawPath(_mutedSpeakerBody(), stroke);
        canvas.drawLine(const Offset(21, 9.5), const Offset(16, 14.5), stroke);
        canvas.drawLine(const Offset(16, 9.5), const Offset(21, 14.5), stroke);
      case StrokeIconKind.minus:
        canvas.drawLine(const Offset(6, 12), const Offset(18, 12), stroke);
      case StrokeIconKind.plus:
        canvas.drawLine(const Offset(6, 12), const Offset(18, 12), stroke);
        canvas.drawLine(const Offset(12, 6), const Offset(12, 18), stroke);
      case StrokeIconKind.power:
        canvas.drawPath(
          Path()
            ..moveTo(18.36, 6.64)
            ..arcToPoint(
              const Offset(5.63, 6.64),
              radius: const Radius.circular(9),
              largeArc: true,
              clockwise: true,
            ),
          stroke,
        );
        canvas.drawLine(const Offset(12, 2), const Offset(12, 12), stroke);
      case StrokeIconKind.gear:
        // v36: the cog outline (round caps/joins; the header passes
        // `strokeWidth: 1.8`) with a hollow r3 hub, replacing the
        // ring-and-spokes glyph.
        canvas.drawPath(_gearOutline(), stroke);
        canvas.drawCircle(const Offset(12, 12), 3, stroke);
    }
  }

  /// The mockup's gear path, absolute coordinates (each `a2 2 0 0 s` is a
  /// 2-unit arc; `clockwise` is the SVG sweep flag).
  static Path _gearOutline() => Path()
    ..moveTo(12.22, 2)
    ..lineTo(11.78, 2)
    ..arcToPoint(const Offset(9.78, 4), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(9.78, 4.18)
    ..arcToPoint(const Offset(8.78, 5.91), radius: const Radius.circular(2))
    ..lineTo(8.35, 6.16)
    ..arcToPoint(const Offset(6.35, 6.16), radius: const Radius.circular(2))
    ..lineTo(6.2, 6.08)
    ..arcToPoint(const Offset(3.47, 6.81), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(3.25, 7.19)
    ..arcToPoint(const Offset(3.98, 9.92), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(4.13, 10.02)
    ..arcToPoint(const Offset(5.13, 11.74), radius: const Radius.circular(2))
    ..lineTo(5.13, 12.25)
    ..arcToPoint(const Offset(4.13, 13.99), radius: const Radius.circular(2))
    ..lineTo(3.98, 14.08)
    ..arcToPoint(const Offset(3.25, 16.81), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(3.47, 17.19)
    ..arcToPoint(const Offset(6.2, 17.92), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(6.35, 17.84)
    ..arcToPoint(const Offset(8.35, 17.84), radius: const Radius.circular(2))
    ..lineTo(8.78, 18.09)
    ..arcToPoint(const Offset(9.78, 19.82), radius: const Radius.circular(2))
    ..lineTo(9.78, 20)
    ..arcToPoint(const Offset(11.78, 22), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(12.22, 22)
    ..arcToPoint(const Offset(14.22, 20), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(14.22, 19.82)
    ..arcToPoint(const Offset(15.22, 18.09), radius: const Radius.circular(2))
    ..lineTo(15.65, 17.84)
    ..arcToPoint(const Offset(17.65, 17.84), radius: const Radius.circular(2))
    ..lineTo(17.8, 17.92)
    ..arcToPoint(const Offset(20.53, 17.19), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(20.75, 16.8)
    ..arcToPoint(const Offset(20.02, 14.07), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(19.87, 13.99)
    ..arcToPoint(const Offset(18.87, 12.25), radius: const Radius.circular(2))
    ..lineTo(18.87, 11.75)
    ..arcToPoint(const Offset(19.87, 10.01), radius: const Radius.circular(2))
    ..lineTo(20.02, 9.92)
    ..arcToPoint(const Offset(20.75, 7.19), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(20.53, 6.81)
    ..arcToPoint(const Offset(17.8, 6.08), radius: const Radius.circular(2), clockwise: false)
    ..lineTo(17.65, 6.16)
    ..arcToPoint(const Offset(15.65, 6.16), radius: const Radius.circular(2))
    ..lineTo(15.22, 5.91)
    ..arcToPoint(const Offset(14.22, 4.18), radius: const Radius.circular(2))
    ..lineTo(14.22, 4)
    ..arcToPoint(const Offset(12.22, 2), radius: const Radius.circular(2), clockwise: false)
    ..close();

  /// `M11 5 6.5 9H3v6h3.5l4.5 4V5Z` (alternate v47b)
  static Path _mutedSpeakerBody() => Path()
    ..moveTo(11, 5)
    ..lineTo(6.5, 9)
    ..lineTo(3, 9)
    ..lineTo(3, 15)
    ..lineTo(6.5, 15)
    ..lineTo(11, 19)
    ..close();

  @override
  bool shouldRepaint(_StrokeIconPainter old) =>
      old.kind != kind || old.color != color || old.strokeWidth != strokeWidth;
}
