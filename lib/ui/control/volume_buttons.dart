import 'dart:async';

import 'package:flutter/widgets.dart';

import '../platform/adaptive_pressable.dart';
import '../settings/stepper_repeat.dart';
import '../theme/app_theme.dart';
import 'control_keys.dart';

/// Hold-to-repeat for VOL − / + (Task 3.6.1): one step on press, the next
/// after [kVolumeHoldDelay], then one every [kVolumeRepeatInterval], flat.
/// The numbers are the KDE widget's `Button.autoRepeat` values, which it
/// in turn copied from the Kotlin app — **not measured** (checklist item
/// 14; TODO 3.6.1 records the Galaxy S25 feel). Each tick re-arms the
/// owner's 400 ms pending mask, so a stale broadcast never lands in a gap
/// between sends (gotcha #1 by construction).
const Duration kVolumeHoldDelay = Duration(milliseconds: 300);
const Duration kVolumeRepeatInterval = Duration(milliseconds: 100);

/// VOL − / +: tap = one step, hold = repeat (Task 3.6.0 / 3.6.1).
///
/// [onMinus] / [onPlus] perform one step and return whether anything
/// moved; a `false` ends a hold at a bound (the owner is the one that knows
/// — this widget keeps no copy of the volume, checklist 9).
///
/// [enabled] is the widget's own gate (Task 3.5.1): the ancestor
/// `DimmedGroup` already blocks pointers while the amp is Off / Booting, but
/// a control that can't work must be inert by itself, not only by where it
/// happens to sit in the tree (checklist item 6). Disabling *mid-hold*
/// releases the press through `AdaptivePressable`, which stops the chain.
class VolumeButtons extends StatelessWidget {
  const VolumeButtons({super.key, required this.enabled, required this.onMinus, required this.onPlus});

  final bool enabled;
  final bool Function() onMinus;
  final bool Function() onPlus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        children: [
          Expanded(
            child: _VolButton(key: ControlKeys.volMinus, glyph: '−', enabled: enabled, onStep: onMinus),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _VolButton(key: ControlKeys.volPlus, glyph: '+', enabled: enabled, onStep: onPlus),
          ),
        ],
      ),
    );
  }
}

class _VolButton extends StatefulWidget {
  const _VolButton({super.key, required this.glyph, required this.enabled, required this.onStep});

  final String glyph;
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
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return AdaptivePressable(
      onTap: _tap,
      onPressedChanged: _pressed,
      enabled: widget.enabled,
      borderRadius: BorderRadius.circular(16),
      pressedScale: 0.94,
      builder: (context, pressed) => Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed && theme.style.isCupertino ? t.surface2 : t.surface,
          border: Border.all(color: t.divider),
          borderRadius: BorderRadius.circular(16),
          boxShadow: t.cardShadow,
        ),
        child: Text(widget.glyph, style: theme.type.display(size: 20, color: t.text)),
      ),
    );
  }
}
