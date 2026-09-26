import 'dart:async';

import 'package:flutter/widgets.dart';

import '../platform/adaptive_pressable.dart';
import '../settings/stepper_repeat.dart';
import '../theme/app_theme.dart';
import '../widgets/stroke_icons.dart';
import 'control_keys.dart';
import 'control_layout.dart';

/// Hold-to-repeat for VOL − / + (Task 3.6.1): one step on press, the next
/// after [kVolumeHoldDelay], then one every [kVolumeRepeatInterval], flat.
/// The numbers are the KDE widget's `Button.autoRepeat` values, which it
/// in turn copied from the Kotlin app — **not measured** (checklist item
/// 14; TODO 3.6.1 records the Galaxy S25 feel). Each tick re-arms the
/// owner's 400 ms pending mask, so a stale broadcast never lands in a gap
/// between sends (gotcha #1 by construction).
const Duration kVolumeHoldDelay = Duration(milliseconds: 300);
const Duration kVolumeRepeatInterval = Duration(milliseconds: 100);

/// The round − · mute · + row (alternate layout): VOL −/+ with tap = one
/// step, hold = repeat (Task 3.6.0 / 3.6.1), and mute in the middle.
///
/// [onMinus] / [onPlus] perform one step and return whether anything
/// moved; a `false` ends a hold at a bound (the owner is the one that knows
/// — this widget keeps no copy of the volume, checklist 9).
///
/// Mute is a toggle, not a readout (v47b): its icon always names the
/// function (the muted speaker) and the circle lights up in the accent
/// while mute is active. It sits inside the volume group, so it dims and
/// goes inert with the dial (the amp cannot mute while Off / Booting).
///
/// [enabled] is the widget's own gate for all three (Task 3.5.1): the
/// ancestor `DimmedGroup` already blocks pointers while the amp is Off /
/// Booting, but a control that can't work must be inert by itself, not
/// only by where it happens to sit in the tree (checklist item 6).
/// Disabling *mid-hold* releases the press through `AdaptivePressable`,
/// which stops the chain.
class VolumeButtons extends StatelessWidget {
  const VolumeButtons({
    super.key,
    required this.enabled,
    required this.onMinus,
    required this.onPlus,
    required this.isMuted,
    required this.onMute,
  });

  final bool enabled;
  final bool Function() onMinus;
  final bool Function() onPlus;
  final bool isMuted;
  final VoidCallback onMute;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _VolButton(
          key: ControlKeys.volMinus,
          icon: StrokeIconKind.minus,
          label: 'Volume down',
          enabled: enabled,
          onStep: onMinus,
        ),
        const SizedBox(width: kRoundButtonGap),
        _MuteButton(isMuted: isMuted, enabled: enabled, onTap: onMute),
        const SizedBox(width: kRoundButtonGap),
        _VolButton(
          key: ControlKeys.volPlus,
          icon: StrokeIconKind.plus,
          label: 'Volume up',
          enabled: enabled,
          onStep: onPlus,
        ),
      ],
    );
  }
}

class _VolButton extends StatefulWidget {
  const _VolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onStep,
  });

  final StrokeIconKind icon;
  final String label;
  final bool enabled;
  final bool Function() onStep;

  @override
  State<_VolButton> createState() => _VolButtonState();
}

class _VolButtonState extends State<_VolButton> {
  late final StepperRepeatController _repeat = StepperRepeatController(
    onTick: () => widget.onStep(),
    firstRepeatAt: kVolumeHoldDelay,
    interval: kVolumeRepeatInterval,
    accel: Duration.zero,
  );

  /// Whether a pointer press already stepped in this activation, so the
  /// tap that follows it does not step again — while a tap with **no**
  /// press (a screen reader's activate action, which never sends a
  /// pointer) still steps exactly once (checklist 6: every entry point).
  /// Cleared a microtask after the release, not in it: on both variants
  /// the press ends *before* `onTap` fires in the same synchronous
  /// handler, and a cancelled press (finger slid off, scroll took over)
  /// gets no `onTap` at all.
  bool _steppedOnPress = false;

  @override
  void dispose() {
    _repeat.dispose();
    super.dispose();
  }

  void _pressed(bool down) {
    if (down) {
      _steppedOnPress = true;
      _repeat.start();
    } else {
      _repeat.stop();
      scheduleMicrotask(() => _steppedOnPress = false);
    }
  }

  void _tap() {
    if (_steppedOnPress) return;
    widget.onStep();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    return RoundButton(
      icon: widget.icon,
      semanticsLabel: widget.label,
      enabled: widget.enabled,
      onTap: _tap,
      onPressedChanged: _pressed,
      background: t.surface,
      pressedBackground: t.surface2,
      border: t.divider,
      foreground: t.text,
    );
  }
}

class _MuteButton extends StatelessWidget {
  const _MuteButton({required this.isMuted, required this.enabled, required this.onTap});

  final bool isMuted;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    return RoundButton(
      key: ControlKeys.muteButton,
      iconKey: ControlKeys.muteIcon,
      icon: StrokeIconKind.speakerMuted,
      semanticsLabel: isMuted ? 'Unmute' : 'Mute',
      toggled: isMuted,
      enabled: enabled,
      onTap: onTap,
      background: isMuted ? t.accentTint(0.14) : t.surface,
      // iOS `.action-btn:active{background:var(--surface-2)}`; the muted
      // circle keeps its tint (`#muteBtn.rb.active` outranks it).
      pressedBackground: isMuted ? null : t.surface2,
      border: isMuted ? t.copperDim : t.divider,
      foreground: isMuted ? t.copperBright : t.text,
    );
  }
}

/// One `.rb` circle: [kRoundButtonSize] across, a 1 dp border, the card
/// shadow, a [kRoundButtonIcon] stroke glyph at 1.8. No text, so the
/// semantics label is the only name it has; [toggled] makes mute read as
/// a switch. [pressedBackground] is the iOS-only pressed tint the VOL
/// buttons had (`surface2`); mute keeps its own colour while pressed.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    required this.enabled,
    required this.onTap,
    required this.background,
    required this.border,
    required this.foreground,
    this.pressedBackground,
    this.onPressedChanged,
    this.toggled,
    this.iconKey,
  });

  final StrokeIconKind icon;
  final String semanticsLabel;
  final bool enabled;
  final VoidCallback onTap;
  final Color background;
  final Color? pressedBackground;
  final Color border;
  final Color foreground;
  final ValueChanged<bool>? onPressedChanged;
  final bool? toggled;
  final Key? iconKey;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return MergeSemantics(
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: toggled,
        label: semanticsLabel,
        child: AdaptivePressable(
          onTap: onTap,
          onPressedChanged: onPressedChanged,
          enabled: enabled,
          borderRadius: BorderRadius.circular(kRoundButtonSize / 2),
          pressedScale: 0.92,
          builder: (context, pressed) {
            final pressedBg = pressedBackground;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: kRoundButtonSize,
              height: kRoundButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pressed && theme.style.isCupertino && pressedBg != null ? pressedBg : background,
                border: Border.all(color: border),
                boxShadow: t.cardShadow,
              ),
              child: Center(
                child: SizedBox.square(
                  key: iconKey,
                  dimension: kRoundButtonIcon,
                  child: StrokeIcon(icon, color: foreground, size: kRoundButtonIcon, strokeWidth: 1.8),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
