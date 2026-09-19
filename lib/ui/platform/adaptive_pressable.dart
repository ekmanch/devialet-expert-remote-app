import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

typedef PressableBuilder = Widget Function(BuildContext context, bool pressed);

/// Press feedback per variant: Material ripple on Android, the mockup's
/// spring scale/opacity on iOS. Exposes [pressed] to the builder so a
/// control can tint itself only while the finger is down (the power
/// button's danger/success cue).
class AdaptivePressable extends StatefulWidget {
  const AdaptivePressable({
    super.key,
    required this.onTap,
    required this.borderRadius,
    required this.builder,
    this.enabled = true,
    this.pressedScale = 0.96,
    this.pressedOpacity = 1.0,
  });

  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final PressableBuilder builder;
  final bool enabled;
  final double pressedScale;
  final double pressedOpacity;

  @override
  State<AdaptivePressable> createState() => _AdaptivePressableState();
}

class _AdaptivePressableState extends State<AdaptivePressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final style = AppTheme.of(context).style;
    final onTap = widget.enabled ? widget.onTap : null;
    final child = widget.builder(context, _pressed);

    if (style.isCupertino) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: onTap == null ? null : (_) => _setPressed(true),
        onTapUp: onTap == null ? null : (_) => _setPressed(false),
        onTapCancel: onTap == null ? null : () => _setPressed(false),
        onTap: onTap,
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: _pressed ? widget.pressedOpacity : 1.0,
            duration: const Duration(milliseconds: 150),
            child: child,
          ),
        ),
      );
    }

    // The ripple must paint *over* the child's own decorated background,
    // hence a transparent Material stacked on top rather than around it.
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
      ],
    );
  }
}
