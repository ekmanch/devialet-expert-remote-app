import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The mockup's `.spinner`: a 2px ring, quarter of it in [color], turning
/// once per 700 ms. Replaces the power glyph while Booting (TODO 2.0.6).
class RingSpinner extends StatefulWidget {
  const RingSpinner({
    super.key,
    required this.color,
    required this.trackColor,
    this.size = 16,
    this.strokeWidth = 2,
    this.period = const Duration(milliseconds: 700),
  });

  final Color color;
  final Color trackColor;
  final double size;
  final double strokeWidth;
  final Duration period;

  @override
  State<RingSpinner> createState() => _RingSpinnerState();
}

class _RingSpinnerState extends State<RingSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _RingPainter(
            turns: _controller.value,
            color: widget.color,
            trackColor: widget.trackColor,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.turns,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double turns;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(strokeWidth / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    final head = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    canvas.drawOval(inset, track);
    // border-top-color: the quarter centred on 12 o'clock, rotated.
    final start = -math.pi * 3 / 4 + turns * 2 * math.pi;
    canvas.drawArc(inset, start, math.pi / 2, false, head);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.turns != turns || old.color != color || old.trackColor != trackColor;
}
