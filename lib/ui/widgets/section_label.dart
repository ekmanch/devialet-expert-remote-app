import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// `.section-label`: 11px/600 Space Grotesk, 0.16em, uppercase, faint.
/// Top margin 22 for the first section, 26 otherwise; 12 below, 2 left.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.first = false});

  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 22 : 26, bottom: 12, left: 2),
      child: Text(
        text.toUpperCase(),
        style: theme.type.display(size: 11, letterSpacingEm: 0.16, color: theme.tokens.textFaint),
      ),
    );
  }
}
