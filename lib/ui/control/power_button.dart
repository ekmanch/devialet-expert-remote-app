import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/control_view_state.dart';
import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/stroke_icons.dart';
import 'control_keys.dart';

/// The power circle on the device card (alternate v44b): 44 dp, a 1 dp
/// border, a 21 dp glyph at stroke 1.8 (`.card-power`, sized for a 360 dp
/// phone). The 2 dp ring while booting sits on the circle's outer edge.
const double kPowerButtonSize = 44;
const double kPowerGlyphSize = 21;
const double kBootRingWidth = 2;

/// One clockwise turn of the booting ring (`animation: spin .9s linear`);
/// 2.5 s under `prefers-reduced-motion` (alternate v47c).
const Duration kBootRingPeriod = Duration(milliseconds: 900);
const Duration kBootRingPeriodReduced = Duration(milliseconds: 2500);

class PowerButtonColors {
  const PowerButtonColors({required this.background, required this.border, required this.foreground});

  final Color background;
  final Color border;
  final Color foreground;
}

/// Power as a round button (alternate layout). The colours are the
/// pre-spike pill's, unchanged: on = text, off = textDim, pressed while on
/// = danger, pressed while off = success/successBright. While booting the
/// glyph stays (amber in dark, the mockup's `#bootGold` gradient in light)
/// and the border becomes the resting track under a [BootRing] — no
/// spinner inside a round button ("style A"). The label that used to sit
/// beside the glyph is now the semantics label only.
///
/// [enabled] is this widget's own gate (checklist 6): inert while booting
/// or without an amp, whatever wraps it. An inert press still swallows the
/// tap (the pressable stays opaque), so it never reaches the card beneath.
class PowerButton extends StatelessWidget {
  const PowerButton({
    super.key,
    required this.power,
    required this.hasAmp,
    required this.enabled,
    required this.onTap,
  });

  static const List<String> labels = ['Power Off', 'Power On', 'Powering on…'];

  final PowerPhase power;
  final bool hasAmp;
  final bool enabled;
  final VoidCallback onTap;

  static String labelFor(PowerPhase power, {required bool hasAmp}) {
    if (!hasAmp) return 'Power Off';
    return switch (power) {
      PowerPhase.on => 'Power Off',
      PowerPhase.off => 'Power On',
      PowerPhase.booting => 'Powering on…',
    };
  }

  static PowerButtonColors colorsFor(AppTokens t, {required PowerPhase power, required bool hasAmp, required bool pressed}) {
    final booting = hasAmp && power == PowerPhase.booting;
    final off = hasAmp && power == PowerPhase.off;
    if (booting) {
      return PowerButtonColors(background: t.surface, border: t.bootRingRest, foreground: t.warningBright);
    }
    if (off) {
      return pressed
          ? PowerButtonColors(background: t.surface, border: t.success, foreground: t.successBright)
          : PowerButtonColors(background: t.surface, border: t.divider, foreground: t.textDim);
    }
    return pressed
        ? PowerButtonColors(background: t.surface, border: t.danger, foreground: t.danger)
        : PowerButtonColors(background: t.surface, border: t.divider, foreground: t.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final booting = hasAmp && power == PowerPhase.booting;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        label: labelFor(power, hasAmp: hasAmp),
        child: AdaptivePressable(
        onTap: onTap,
        enabled: enabled,
        borderRadius: BorderRadius.circular(kPowerButtonSize / 2),
        pressedScale: 0.92,
        builder: (context, pressed) {
          final c = colorsFor(t, power: power, hasAmp: hasAmp, pressed: pressed);
          Widget glyph = StrokeIcon(StrokeIconKind.power, color: c.foreground, size: kPowerGlyphSize, strokeWidth: 1.8);
          final gradient = booting ? t.bootGlyphGradientColors : null;
          if (gradient != null) {
            glyph = ShaderMask(
              blendMode: BlendMode.srcIn,
              // `#bootGold`: userSpaceOnUse (3,2)→(21,22) in the 24-unit box.
              shaderCallback: (bounds) => LinearGradient(
                begin: const Alignment(-0.75, -0.833),
                end: const Alignment(0.75, 0.833),
                colors: gradient,
                stops: AppTokens.bootGlyphGradientStops,
              ).createShader(Offset.zero & bounds.size),
              child: glyph,
            );
          }
          return SizedBox.square(
            dimension: kPowerButtonSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // iOS `.action-btn:active{background:var(--surface-2)}`.
                    color: pressed && theme.style.isCupertino ? t.surface2 : c.background,
                    border: Border.all(color: c.border),
                    boxShadow: t.cardShadow,
                  ),
                  child: Center(
                    child: SizedBox.square(key: ControlKeys.powerIcon, dimension: kPowerGlyphSize, child: glyph),
                  ),
                ),
                if (booting) BootRing(color: t.bootRing),
              ],
            ),
          );
        },
        ),
      ),
    );
  }
}

/// The booting indicator: the circle's own outline becomes a comet
/// (transparent 0°–120°, ramping to full colour at 340°, a hard cut) that
/// turns clockwise once per [kBootRingPeriod]. Reduced motion slows it to
/// [kBootRingPeriodReduced] rather than stopping it — the ring *is* the
/// "powering on" signal, so it must keep moving.
class BootRing extends StatefulWidget {
  const BootRing({super.key, required this.color});

  final Color color;

  @override
  State<BootRing> createState() => _BootRingState();
}

class _BootRingState extends State<BootRing> with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(vsync: this, duration: kBootRingPeriod);
  bool? _reduced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Same discipline as DeviceDot: re-sync on the setting itself, not on
    // every MediaQuery change.
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reduced) {
      _reduced = reduced;
      _sync();
    }
  }

  /// A running controller ignores a `duration` change, so stop and go.
  void _sync() {
    _turns.stop();
    _turns.value = 0;
    _turns.duration = (_reduced ?? false) ? kBootRingPeriodReduced : kBootRingPeriod;
    _turns.repeat();
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _turns,
      builder: (_, _) => CustomPaint(painter: BootRingPainter(turns: _turns.value, color: widget.color)),
    );
  }
}

/// One flat [color] whose alpha ramps along the sweep — never a hue
/// gradient (alternate v47e). Painted [kBootRingWidth] wide, centred one
/// dp inside the edge so it covers the circle's 1 dp border.
class BootRingPainter extends CustomPainter {
  const BootRingPainter({required this.turns, required this.color});

  /// Fraction of one clockwise revolution, 0..1.
  final double turns;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - kBootRingWidth / 2;
    final clear = color.withValues(alpha: 0);
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: [clear, clear, color, clear],
      stops: const [0, 120 / 360, 340 / 360, 341 / 360],
      // CSS `conic-gradient(from 0deg …)` starts at 12 o'clock; Flutter's
      // sweep starts at 3 o'clock. Both turn clockwise on screen.
      transform: GradientRotation(turns * 2 * math.pi - math.pi / 2),
    ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = kBootRingWidth
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(BootRingPainter old) => old.turns != turns || old.color != color;
}
