import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The rows' trailing chevron (`.chevron-r` / `›`), painted like
/// [CheckMark] so it carries the same weight: the 15 px character painted
/// 13 × 21 px on the S25 against the tick's 42 × 32 (owner, 2026-09-23).
/// `textFaint`, 18 px box, 2-unit stroke.
class ChevronMark extends StatelessWidget {
  const ChevronMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    return CustomPaint(size: Size.square(size), painter: ChevronMarkPainter(color: t.textFaint));
  }
}

class ChevronMarkPainter extends CustomPainter {
  const ChevronMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 20;
    canvas.scale(scale, scale);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(7, 4)
        ..lineTo(13, 10)
        ..lineTo(7, 16),
      stroke,
    );
  }

  @override
  bool shouldRepaint(ChevronMarkPainter old) => old.color != color;
}

/// The sheets' "selected" tick (`.source-check`), painted instead of the
/// ✓ character: the mockup's 14 px character was too light to mark the
/// selected row on the S25 (owner, 2026-09-23), so it is a 2-unit stroke
/// in the glyphs' 20-unit box at [size] (18 by default), flat
/// `copperBright` in both themes like the mockup.
class CheckMark extends StatelessWidget {
  const CheckMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    return CustomPaint(size: Size.square(size), painter: CheckMarkPainter(color: t.copperBright));
  }
}

class CheckMarkPainter extends CustomPainter {
  const CheckMarkPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 20;
    canvas.scale(scale, scale);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(3.5, 10.5)
        ..lineTo(8, 15)
        ..lineTo(16.5, 5.5),
      stroke,
    );
  }

  @override
  bool shouldRepaint(CheckMarkPainter old) => old.color != color;
}
