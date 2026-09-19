import 'package:flutter/widgets.dart';

/// The mockups' four inline SVGs (24-unit viewBox, `stroke: currentColor`,
/// `fill: none`) as painters, tinted through the framework rather than the
/// asset (checklist item 18).
enum StrokeIconKind { gear, speaker, speakerMuted, power }

class StrokeIcon extends StatelessWidget {
  const StrokeIcon(this.kind, {super.key, required this.color, this.size = 16});

  final StrokeIconKind kind;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _StrokeIconPainter(kind: kind, color: color)),
    );
  }
}

class _StrokeIconPainter extends CustomPainter {
  const _StrokeIconPainter({required this.kind, required this.color});

  final StrokeIconKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    canvas.scale(scale, scale);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    switch (kind) {
      case StrokeIconKind.speaker:
        canvas.drawPath(_speakerBody(), stroke);
        canvas.drawPath(
          Path()
            ..moveTo(15.5, 8.5)
            ..arcToPoint(const Offset(15.5, 15.5), radius: const Radius.circular(5), clockwise: true),
          stroke,
        );
      case StrokeIconKind.speakerMuted:
        canvas.drawPath(_speakerBody(), stroke);
        canvas.drawLine(const Offset(23, 9), const Offset(17, 15), stroke);
        canvas.drawLine(const Offset(17, 9), const Offset(23, 15), stroke);
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
        canvas.drawCircle(const Offset(12, 12), 7, stroke..strokeWidth = 1.8);
        canvas.drawCircle(const Offset(12, 12), 2, Paint()..color = color);
        final spoke = Paint()
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = color;
        const spokes = [
          (Offset(19.2, 12), Offset(21.6, 12)),
          (Offset(15.6, 18.24), Offset(16.8, 20.31)),
          (Offset(8.4, 18.24), Offset(7.2, 20.31)),
          (Offset(4.8, 12), Offset(2.4, 12)),
          (Offset(8.4, 5.76), Offset(7.2, 3.69)),
          (Offset(15.6, 5.76), Offset(16.8, 3.69)),
        ];
        for (final (a, b) in spokes) {
          canvas.drawLine(a, b, spoke);
        }
    }
  }

  /// `M11 5 6 9H2v6h4l5 4V5Z`
  static Path _speakerBody() => Path()
    ..moveTo(11, 5)
    ..lineTo(6, 9)
    ..lineTo(2, 9)
    ..lineTo(2, 15)
    ..lineTo(6, 15)
    ..lineTo(11, 19)
    ..close();

  @override
  bool shouldRepaint(_StrokeIconPainter old) => old.kind != kind || old.color != color;
}
