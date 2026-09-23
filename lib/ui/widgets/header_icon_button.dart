import 'package:flutter/widgets.dart';

import '../platform/adaptive_pressable.dart';
import '../theme/app_tokens.dart';

/// A header icon button as a bare glyph (v36, `.phone .icon-btn`): no
/// surface, border or shadow — the convention for both a Material top-bar
/// action and an iOS nav-bar item. The 44 dp box stays as the tap target,
/// with a neutral press disc instead of a visible container; the iOS
/// spring scale is off here (`transform: none`), as the mockup has it.
///
/// [overhang] lets the box stick out past the content edge so the glyph
/// edge lines up with the cards (`margin-right: -10px` on the gear,
/// `margin-left: -12px` on the Android back arrow): positive = past the
/// right edge, negative = past the left. The box paints in full, but the
/// part outside the screen's content padding is not tappable — Flutter
/// hit tests stop at each ancestor's bounds — so the effective target is
/// `44 − |overhang|` wide (34 / 32 dp) by 44 tall.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.onTap,
    required this.child,
    this.overhang = 0,
  });

  static const double size = 44;

  final VoidCallback? onTap;
  final Widget child;
  final double overhang;

  @override
  Widget build(BuildContext context) {
    final button = AdaptivePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      pressedScale: 1,
      pressedOpacity: 1,
      builder: (context, pressed) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: pressed ? AppTokens.iconPressHighlight : null,
        ),
        child: child,
      ),
    );
    if (overhang == 0) return button;
    return SizedBox(
      width: size - overhang.abs(),
      height: size,
      child: OverflowBox(
        minWidth: size,
        maxWidth: size,
        alignment: overhang > 0 ? Alignment.centerLeft : Alignment.centerRight,
        child: button,
      ),
    );
  }
}
