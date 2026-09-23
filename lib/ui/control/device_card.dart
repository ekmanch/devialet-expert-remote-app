import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/control_view_state.dart';
import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../widgets/dimmed_group.dart';
import 'control_keys.dart';

enum DeviceDotState { connected, off, none, booting }

/// One leg of the booting pulse (1 → 0.35 or back); the full cycle is twice this.
const Duration kDotPulseLeg = Duration(milliseconds: 550);

/// The 10px status dot: copper glow (connected), hollow ring (off), dashed
/// ring (none), pulsing amber (booting: opacity 1 → 0.35 → 1 over one
/// 1.1 s cycle, i.e. 550 ms each way, as the KDE widget's `AmpHeader.qml`
/// and the mockup's `dotPulse 1.1s`). The controller's `duration` is one
/// *leg* because `repeat(reverse: true)` plays it both ways — 1100 ms here
/// was the Task 3.5.3 bug, a pulse at half the widget's speed
/// (checklist 15: the mockup's declared number described the whole cycle).
class DeviceDot extends StatefulWidget {
  const DeviceDot({super.key, required this.state, this.size = defaultSize});

  /// The mockup declares 10 px; on the S25 that read as a speck next to
  /// the 15.75 px glyph boxes (owner, 2026-09-23), so the card and the
  /// amp list use 13 — the painted glyphs' ring diameter (7.6 · 2 / 20 of
  /// the box ≈ 12) plus a hair, since a filled disc reads smaller than
  /// a ring of the same size.
  static const double defaultSize = 13;

  final DeviceDotState state;
  final double size;

  @override
  State<DeviceDot> createState() => _DeviceDotState();
}

class _DeviceDotState extends State<DeviceDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: kDotPulseLeg,
  );

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(DeviceDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();
  }

  void _syncPulse() {
    if (widget.state == DeviceDotState.booting) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    final size = widget.size;
    final Widget dot = switch (widget.state) {
      DeviceDotState.connected => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.isDark ? t.copperBright : null,
          gradient: t.isDark
              ? null
              : const RadialGradient(
                  center: Alignment(-0.36, -0.44),
                  colors: [Color(0xFFFCECC0), Color(0xFFF0A623), Color(0xFFA8710B)],
                  stops: [0, 0.38, 1],
                ),
          boxShadow: t.isDark ? [BoxShadow(color: t.dotGlow, blurRadius: 8, spreadRadius: 2)] : null,
        ),
      ),
      DeviceDotState.off => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: t.textFaint, width: 1.5),
        ),
      ),
      DeviceDotState.none => CustomPaint(
        size: Size.square(size),
        painter: _DashedRingPainter(color: t.textFaint, strokeWidth: 1.5),
      ),
      DeviceDotState.booting => FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 0.35).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        ),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: t.warningBright,
            boxShadow: const [BoxShadow(color: Color(0x80E0B563), blurRadius: 8, spreadRadius: 2)],
          ),
        ),
      ),
    };
    return SizedBox.square(dimension: size, child: Center(child: dot));
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter({required this.color, required this.strokeWidth});

  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = color;
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
    const dashes = 6;
    const gapFraction = 0.45;
    final sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * sweep, sweep * (1 - gapFraction), false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color || old.strokeWidth != strokeWidth;
}

/// The amp card: whole row is the tap target (TODO 2.0.2). Shows
/// `model ?? name`, the IP with a status word, and the dot. "Connected"
/// describes the UDP link, so it stays while the amp is Off.
class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key, required this.state, required this.onTap});

  final ControlViewState state;
  final VoidCallback onTap;

  static DeviceDotState dotStateFor(ControlViewState s) {
    if (!s.hasAmp) return DeviceDotState.none;
    return switch (s.power) {
      PowerPhase.on => DeviceDotState.connected,
      PowerPhase.off => DeviceDotState.off,
      PowerPhase.booting => DeviceDotState.booting,
    };
  }

  static String nameFor(ControlViewState s) => s.hasAmp ? s.selectedAmp!.displayName : 'No Amplifier';

  static String subtitleFor(ControlViewState s) {
    if (!s.hasAmp) return 'Tap to connect';
    if (s.power == PowerPhase.booting) return 'Booting…';
    return '${s.selectedAmp!.ip} · Connected';
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return AdaptivePressable(
      key: ControlKeys.deviceCard,
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      pressedScale: 0.97,
      pressedOpacity: 0.85,
      builder: (context, pressed) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.divider),
          borderRadius: BorderRadius.circular(18),
          boxShadow: t.cardShadow,
        ),
        child: Row(
          children: [
            DeviceDot(key: ControlKeys.deviceDot, state: dotStateFor(state)),
            const SizedBox(width: 12),
            Expanded(
              child: DimmedGroup(
                dimmed: !state.hasAmp,
                opacity: 0.5,
                blockTaps: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        nameFor(state),
                        key: ControlKeys.deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.type.body(size: 15, weight: FontWeight.w600, color: t.text),
                      ),
                    ),
                    Text(
                      subtitleFor(state),
                      key: ControlKeys.deviceSub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.type.mono(size: 12.5, letterSpacingEm: 0.01, color: t.textDim),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('Change ›', style: theme.type.body(size: 14, color: t.textFaint)),
          ],
        ),
      ),
    );
  }
}
