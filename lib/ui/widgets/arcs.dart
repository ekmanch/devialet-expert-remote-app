import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The mockups' three-arc motif (48-unit viewBox, round caps): the amp
/// picker's animated "listening" arcs and the source sheet's static
/// corner decoration share this geometry.
///
/// `M22 13 A9 9 0 1 0 31 22` / `M9 29.5 A15 15 0 0 0 36.5 18.1` /
/// `M20.2 42.9 A21 21 0 0 0 42.7 18.4`.
class ArcsPainter extends CustomPainter {
  const ArcsPainter({required this.colors, required this.strokeWidth});

  /// One colour per arc, innermost first; opacity goes in the colour.
  final List<Color> colors;

  /// In viewBox units (scaled with the widget).
  final double strokeWidth;

  static const double viewBox = 48;

  static final List<Path> _arcs = [
    Path()
      ..moveTo(22, 13)
      ..arcToPoint(const Offset(31, 22), radius: const Radius.circular(9), largeArc: true, clockwise: false),
    Path()
      ..moveTo(9, 29.5)
      ..arcToPoint(const Offset(36.5, 18.1), radius: const Radius.circular(15), clockwise: false),
    Path()
      ..moveTo(20.2, 42.9)
      ..arcToPoint(const Offset(42.7, 18.4), radius: const Radius.circular(21), clockwise: false),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / viewBox;
    canvas.scale(scale, scale);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _arcs.length; i++) {
      canvas.drawPath(_arcs[i], paint..color = colors[i]);
    }
  }

  @override
  bool shouldRepaint(ArcsPainter old) => old.strokeWidth != strokeWidth || !_sameColors(old.colors);

  bool _sameColors(List<Color> other) {
    if (other.length != colors.length) return false;
    for (var i = 0; i < colors.length; i++) {
      if (other[i] != colors[i]) return false;
    }
    return true;
  }
}

/// The source sheet's decorative arcs (v23): 120 dp, meant to bleed off
/// the panel's top-right corner (the caller positions it at `top −33,
/// right −39` and the sheet frame clips it). Stroke 2.2; innermost arc
/// accent at 55 %, the outer two `copperDim` at 55 % / 30 % — all three
/// the accent in light.
class SheetArcs extends StatelessWidget {
  const SheetArcs({super.key});

  static const double size = 120;
  static const Offset offset = Offset(-39, -33);

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    final outer = t.isDark ? t.copperDim : t.copperBright;
    return IgnorePointer(
      child: CustomPaint(
        size: const Size.square(size),
        painter: ArcsPainter(
          strokeWidth: 2.2,
          colors: [
            t.copperBright.withValues(alpha: 0.55),
            outer.withValues(alpha: 0.55),
            outer.withValues(alpha: 0.3),
          ],
        ),
      ),
    );
  }
}

/// The amp picker's "listening" arcs: 26 dp, stroke 3.4, each arc
/// blinking `opacity .15 → 1 (at 30 %) → .15` over 1.8 s, the three
/// staggered by 250 ms. Only exists while the picker's list view is
/// shown, so it only animates then. Under reduced motion the arcs sit
/// static at full opacity, as the mockup's `prefers-reduced-motion` rule.
class ListeningArcs extends StatefulWidget {
  const ListeningArcs({super.key});

  static const double size = 26;
  static const Duration period = Duration(milliseconds: 1800);
  static const Duration stagger = Duration(milliseconds: 250);
  static const double restOpacity = 0.15;
  static const double peakAt = 0.3;

  /// Opacity of arc [index] at [t] ∈ [0, 1) of the period.
  static double opacityAt(int index, double t) {
    final delay = index * stagger.inMilliseconds / period.inMilliseconds;
    final phase = (t - delay) % 1.0;
    final rise = phase < peakAt ? phase / peakAt : 1 - (phase - peakAt) / (1 - peakAt);
    return restOpacity + (1 - restOpacity) * rise;
  }

  @override
  State<ListeningArcs> createState() => _ListeningArcsState();
}

class _ListeningArcsState extends State<ListeningArcs> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: ListeningArcs.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: const Size.square(ListeningArcs.size),
        painter: ArcsPainter(
          strokeWidth: 3.4,
          colors: [
            for (var i = 0; i < 3; i++)
              t.listenArc.withValues(alpha: reduced ? 1 : ListeningArcs.opacityAt(i, _controller.value)),
          ],
        ),
      ),
    );
  }
}
