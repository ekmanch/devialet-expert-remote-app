import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// The mockup's `.settings-group`: a surface card (r16, 1 px divider
/// border, card shadow) whose rows are separated by 1 px dividers inset
/// 16 from the left.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.divider),
        borderRadius: BorderRadius.circular(16),
        boxShadow: t.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Container(height: 1, margin: const EdgeInsets.only(left: 16), color: t.divider),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
