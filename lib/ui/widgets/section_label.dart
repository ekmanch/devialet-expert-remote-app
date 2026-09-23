import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';

/// `.section-label`: 11px/600 Space Grotesk, 0.16em, uppercase, faint.
/// Top margin 22 for the first section, 26 otherwise; 12 below, 2 left.
///
/// [accent] is the Settings-screen variant (v28/v29/v32): weight 700 and
/// the accent moved here from the numbers — a gold gradient clipped to
/// the letters in light, flat `copperBright` in dark. The Control screen
/// keeps the faint version.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.first = false, this.accent = false});

  final String text;
  final bool first;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final label = Text(
      text.toUpperCase(),
      style: theme.type.display(
        size: 11,
        weight: accent ? FontWeight.w700 : FontWeight.w600,
        letterSpacingEm: 0.16,
        color: accent ? t.copperBright : t.textFaint,
      ),
    );
    final gradient = accent ? t.settingsHeadingGradientColors : null;
    final child = gradient == null
        ? label
        : ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: gradient,
              stops: AppTokens.settingsHeadingGradientStops,
            ).createShader(Offset.zero & bounds.size),
            child: label,
          );
    return Padding(
      padding: EdgeInsets.only(top: first ? 22 : 26, bottom: 12, left: 2),
      // `width: fit-content`, so the gradient spans the letters, not the row.
      child: Align(alignment: Alignment.centerLeft, child: child),
    );
  }
}
