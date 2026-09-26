import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../domain/control_view_state.dart';
import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../widgets/check_mark.dart';
import '../widgets/dimmed_group.dart';
import 'control_keys.dart';
import 'power_button.dart';

enum DeviceDotState { connected, off, none, booting, waiting }

/// One leg of the booting pulse (1 → 0.35 or back); the full cycle is twice this.
const Duration kDotPulseLeg = Duration(milliseconds: 550);

/// One leg of the waiting-ring pulse (1 → 0.3 or back). The v44 mockup
/// declares `ampRingPulse 1.8s` for the whole 0 → 50 % → 100 % cycle, so
/// the leg is half of it (the 3.5.3 lesson, checklist 15).
const Duration kWaitingPulseLeg = Duration(milliseconds: 900);

/// The 10px status dot: copper glow (connected), hollow ring (off), dashed
/// ring (none), pulsing amber (booting: opacity 1 → 0.35 → 1 over one
/// 1.1 s cycle, i.e. 550 ms each way, as the KDE widget's `AmpHeader.qml`
/// and the mockup's `dotPulse 1.1s`), pulsing copper ring (waiting, v44:
/// 1 → 0.3 → 1 over 1.8 s). The controller's `duration` is one *leg*
/// because `repeat(reverse: true)` plays it both ways — 1100 ms here was
/// the Task 3.5.3 bug, a pulse at half the widget's speed (checklist 15:
/// the mockup's declared number described the whole cycle). Both pulses
/// hold still under the platform's reduced-motion setting (the mockup's
/// `prefers-reduced-motion`).
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
  bool? _reduced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-sync only when the reduced-motion setting itself changes (the
    // first build included), not on every MediaQuery change — a keyboard
    // inset must not restart the pulse.
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced != _reduced) {
      _reduced = reduced;
      _syncPulse();
    }
  }

  @override
  void didUpdateWidget(DeviceDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _syncPulse();
  }

  bool get _pulses => widget.state == DeviceDotState.booting || widget.state == DeviceDotState.waiting;

  /// Restarts from opacity 1 on every state change: a running controller
  /// ignores a `duration` change, so booting ↔ waiting must stop and go.
  void _syncPulse() {
    _pulse.stop();
    _pulse.value = 0;
    if (_pulses && !(_reduced ?? false)) {
      _pulse.duration = widget.state == DeviceDotState.waiting ? kWaitingPulseLeg : kDotPulseLeg;
      _pulse.repeat(reverse: true);
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
      // v44 `.device-dot.waiting` / `.amp-option.offline.connected .amp-dot`:
      // a 1.8 px accent ring, pulsing 1 → 0.3 → 1.
      DeviceDotState.waiting => FadeTransition(
        opacity: Tween<double>(begin: 1.0, end: 0.3).animate(
          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
        ),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: t.copperBright, width: 1.8),
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
/// `model ?? name`, the IP, the dot — and, on the alternate layout, the
/// power circle (v44b): the card is two tap targets, "the amp area opens
/// the amp sheet" (dot, name, chevron) and "the circle is power", split by
/// a hairline. The subtitle is the bare IP while On or Off (the dot
/// carries the link state; "· Connected" went with v44b). While *waiting*
/// (Task 3.9.0, v44) the selection stays named, the dot is the pulsing
/// accent ring and the status word — "Reconnecting…" for an amp heard
/// before, "Connecting…" for one never heard — is the accent colour,
/// followed by the IP only when the amp has a name of its own (a typed IP
/// is already the title).
///
/// The power circle is the pressable's `overlay`, so a press on it never
/// opens the sheet nor plays the card's press feedback; while no amp is
/// selected or the amp is waiting it dims to 0.35 and *absorbs* its taps
/// (owner decision 2026-09-26). The row reserves the circle's slot with a
/// same-size placeholder and the overlay is inset by the card's own
/// padding + border, from the same constants, so the two cannot drift.
class DeviceCard extends StatelessWidget {
  const DeviceCard({super.key, required this.state, required this.onTap, required this.onPower});

  final ControlViewState state;
  final VoidCallback onTap;
  final VoidCallback onPower;

  /// `.device-card{padding:14px 16px; border:1px; gap:8px}` (alternate
  /// v44b: 8, was 12) and the `.card-divider` 1 × 30. `Container` adds the
  /// border to the padding, so content starts at padding + border.
  static const double paddingH = 16;
  static const double paddingV = 14;
  static const double borderWidth = 1;
  static const double gap = 8;
  static const double dividerHeight = 30;

  static DeviceDotState dotStateFor(ControlViewState s) {
    if (s.isWaiting) return DeviceDotState.waiting;
    if (!s.hasAmp) return DeviceDotState.none;
    return switch (s.power) {
      PowerPhase.on => DeviceDotState.connected,
      PowerPhase.off => DeviceDotState.off,
      PowerPhase.booting => DeviceDotState.booting,
    };
  }

  static String nameFor(ControlViewState s) => s.selectedAmp?.displayName ?? 'No Amplifier';

  /// The waiting status word (mockup `ampWaitingText`).
  static String waitingStatusFor(AmpRef amp) => amp.heard ? 'Reconnecting…' : 'Connecting…';

  /// The status line as plain text (the waiting line is rendered two-toned
  /// by [subtitleSpanFor]; this is its text).
  static String subtitleFor(ControlViewState s) {
    final amp = s.selectedAmp;
    if (amp == null) return 'Tap to connect';
    if (s.isWaiting) return amp.name.isEmpty ? waitingStatusFor(amp) : '${waitingStatusFor(amp)} · ${amp.ip}';
    if (s.power == PowerPhase.booting) return 'Booting…';
    return amp.ip;
  }

  static TextSpan subtitleSpanFor(ControlViewState s, TextStyle base, Color accent) {
    final amp = s.selectedAmp;
    if (amp == null || !s.isWaiting) return TextSpan(text: subtitleFor(s), style: base);
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: waitingStatusFor(amp), style: base.copyWith(color: accent)),
        if (amp.name.isNotEmpty) TextSpan(text: ' · ${amp.ip}'),
      ],
    );
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
      overlay: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: paddingH + borderWidth),
          child: DimmedGroup(
            key: ControlKeys.powerButton,
            // `.device-dot.none / .waiting` → `.card-power{opacity:.35}`.
            dimmed: !state.hasAmp,
            opacity: 0.35,
            absorb: true,
            child: PowerButton(
              power: state.power,
              hasAmp: state.hasAmp,
              enabled: state.powerEnabled,
              onTap: onPower,
            ),
          ),
        ),
      ),
      builder: (context, pressed) => Container(
        padding: const EdgeInsets.symmetric(horizontal: paddingH, vertical: paddingV),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.divider, width: borderWidth),
          borderRadius: BorderRadius.circular(18),
          boxShadow: t.cardShadow,
        ),
        child: Row(
          children: [
            DeviceDot(key: ControlKeys.deviceDot, state: dotStateFor(state)),
            const SizedBox(width: gap),
            Expanded(
              child: DimmedGroup(
                // Only "No Amplifier" is dim; a waiting selection is named at
                // full strength (mockup: `.device-info.dim` on None only).
                dimmed: state.selectedAmp == null,
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
                    if (state.isWaiting)
                      Text.rich(
                        subtitleSpanFor(
                          state,
                          theme.type.mono(size: 12.5, letterSpacingEm: 0.01, color: t.textDim),
                          t.copperBright,
                        ),
                        key: ControlKeys.deviceSub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
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
            const SizedBox(width: gap),
            ChevronMark(color: t.textFaint),
            const SizedBox(width: gap),
            SizedBox(
              key: ControlKeys.deviceDivider,
              width: 1,
              height: dividerHeight,
              child: ColoredBox(color: t.divider),
            ),
            const SizedBox(width: gap),
            // The power circle's slot; the circle itself is the overlay.
            const SizedBox.square(dimension: kPowerButtonSize),
          ],
        ),
      ),
    );
  }
}
