import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

typedef PressableBuilder = Widget Function(BuildContext context, bool pressed);

/// Press feedback per variant: Material ripple on Android, the mockup's
/// spring scale/opacity on iOS. Exposes [pressed] to the builder so a
/// control can tint itself only while the finger is down (the power
/// button's danger/success cue).
///
/// [overlay] is a second tap target *inside* the feedback surface (the
/// device card's power circle, alternate v44b): it is laid over the whole
/// child and hit-tested first, so a press on its opaque parts never
/// reaches this widget's own gesture layer — no [onTap], no ripple, no
/// scale — while its hit-transparent parts (an `Align`'s empty region)
/// fall through to the child as usual. On iOS the overlay sits *above the
/// card's detector but inside its scale/opacity*, so a press on the card
/// scales the overlay with it, and a press on the overlay scales nothing
/// (mockup: `.device-card:has(#powerBtn:active){transform:none}`). This
/// is structural (checklist 28): nesting the overlay's detector inside the
/// card's would let `TapGestureRecognizer`'s 100 ms deadline fire the
/// card's tap-down on every held press before the arena resolves.
class AdaptivePressable extends StatefulWidget {
  const AdaptivePressable({
    super.key,
    required this.onTap,
    required this.borderRadius,
    required this.builder,
    this.enabled = true,
    this.pressedScale = 0.96,
    this.pressedOpacity = 1.0,
    this.onPressedChanged,
    this.overlay,
  });

  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final PressableBuilder builder;
  final bool enabled;
  final double pressedScale;
  final double pressedOpacity;

  /// Fires on press start / end (tap-down, tap-up, cancel) — the seam for
  /// hold-to-repeat, which must step on press, not on tap.
  final ValueChanged<bool>? onPressedChanged;

  /// An independent tap target stacked over the child; see the class doc.
  final Widget? overlay;

  @override
  State<AdaptivePressable> createState() => _AdaptivePressableState();
}

class _AdaptivePressableState extends State<AdaptivePressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
    widget.onPressedChanged?.call(value);
  }

  /// A control disabled *while pressed* (the amp went Off under a held VOL
  /// button — Task 3.6.1, checklist 6/28) must release here, for every
  /// user of this widget at once: the Cupertino branch nulls its up/cancel
  /// handlers when disabled, so they would never fire, and `InkResponse`
  /// clears its own highlight without calling `onHighlightChanged`. The
  /// release reaches [AdaptivePressable.onPressedChanged], which is what
  /// stops a hold-to-repeat chain.
  @override
  void didUpdateWidget(AdaptivePressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) _setPressed(false);
  }

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.of(context).style;
    final onTap = widget.enabled ? widget.onTap : null;
    final child = widget.builder(context, _pressed);

    final overlay = widget.overlay;

    if (style.isCupertino) {
      final detector = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTap == null ? null : (_) => _setPressed(true),
        onTapUp: onTap == null ? null : (_) => _setPressed(false),
        onTapCancel: onTap == null ? null : () => _setPressed(false),
        onTap: onTap,
        child: child,
      );
      return AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _pressed ? widget.pressedOpacity : 1.0,
          duration: const Duration(milliseconds: 150),
          child: overlay == null
              ? detector
              : Stack(
                  fit: StackFit.passthrough,
                  children: [detector, Positioned.fill(child: overlay)],
                ),
        ),
      );
    }

    // The ripple must paint *over* the child's own decorated background,
    // hence a transparent Material stacked on top rather than around it;
    // the overlay goes over the ink layer so it is hit-tested first.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: widget.borderRadius,
              onTap: onTap,
              onHighlightChanged: _setPressed,
              child: const SizedBox.expand(),
            ),
          ),
        ),
        if (overlay != null) Positioned.fill(child: overlay),
      ],
    );
  }
}
