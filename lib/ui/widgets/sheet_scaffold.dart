import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Handle + title + subtitle + scrollable body, per the mockups' sheet
/// panel (padding 10 18 20; handle 36×4 Android / 36×5 iOS; title 17/600
/// display; subtitle 12 mono faint).
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final handle = theme.style.sheetHandleSize;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: handle.width,
              height: handle.height,
              margin: EdgeInsets.only(top: theme.style.isCupertino ? 4 : 2, bottom: 14),
              decoration: BoxDecoration(
                color: t.isDark ? t.surface3 : t.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Text(title, style: theme.type.display(size: 17, color: t.text)),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 14),
            child: Text(subtitle, style: theme.type.mono(size: 12, color: t.textFaint)),
          ),
          Flexible(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
  }
}
