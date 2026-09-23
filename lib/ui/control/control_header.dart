import 'package:flutter/widgets.dart';

import '../platform/platform_style.dart';
import '../theme/app_theme.dart';
import '../widgets/header_icon_button.dart';
import '../widgets/stroke_icons.dart';
import 'control_keys.dart';
import 'control_layout.dart';

/// Wordmark + title (Android) or eyebrow + large title (iOS), with the
/// settings gear, which pushes the Settings screen (Task 3.4.x). The gear
/// is a bare 23 dp glyph in a 44 dp target (v36), overhanging the content
/// edge by 10 so the glyph lines up with the cards.
class ControlHeader extends StatelessWidget {
  const ControlHeader({super.key, this.onSettingsTap});

  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final eyebrow = theme.style.headerKind == HeaderKind.eyebrow;

    return Padding(
      key: ControlKeys.header,
      padding: eyebrow
          ? const EdgeInsets.fromLTRB(2, 14, 2, kControlHeaderBottomEyebrow)
          : const EdgeInsets.fromLTRB(0, 16, 0, kControlHeaderBottom),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(bottom: eyebrow ? 2 : 4),
                  child: _Wordmark(
                    style: theme.type.display(
                      size: eyebrow ? 14 : 15,
                      letterSpacingEm: eyebrow ? 0.2 : 0.22,
                      color: t.copperBright,
                    ),
                    gradientColors: t.wordmarkGradientColors,
                  ),
                ),
                Text(
                  'Expert Pro Remote',
                  style: eyebrow
                      ? theme.type.display(size: 30, weight: FontWeight.w700, letterSpacingEm: -0.015, color: t.text)
                      : theme.type.display(size: 26, letterSpacingEm: -0.01, color: t.text),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: EdgeInsets.only(top: eyebrow ? 2 : 0),
            child: HeaderIconButton(
              key: ControlKeys.gearButton,
              onTap: onSettingsTap,
              overhang: 10,
              child: StrokeIcon(StrokeIconKind.gear, color: t.textDim, size: 23),
            ),
          ),
        ],
      ),
    );
  }
}

/// "DEVIALET" — flat `copperBright`, or, when the theme supplies
/// [gradientColors] (light), the mockups' foil sheen: a left-to-right
/// gradient clipped to the glyphs (`background-clip: text`), darkest on the
/// left, brightest on the right. `ShaderMask` + `srcIn` is Flutter's
/// equivalent; the text's own colour only defines the mask.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.style, required this.gradientColors});

  final TextStyle style;
  final List<Color>? gradientColors;

  @override
  Widget build(BuildContext context) {
    final text = Text('DEVIALET', key: ControlKeys.wordmark, style: style);
    final colors = gradientColors;
    if (colors == null) return text;
    return ShaderMask(
      key: ControlKeys.wordmarkSheen,
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: colors,
      ).createShader(Offset.zero & bounds.size),
      child: text,
    );
  }
}
