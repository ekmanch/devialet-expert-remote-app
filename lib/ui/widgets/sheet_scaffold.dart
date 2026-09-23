import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Handle + title + subtitle + scrollable body, per the mockups' sheet
/// panel (padding 10 18 20; handle 36×4 Android / 36×5 iOS; title 17/600
/// display; subtitle 12 mono, `textDim` since v26 — it carries real
/// information). [subtitleLeading] sits before the subtitle (the amp
/// picker's listening arcs); [backdrop] paints behind everything at
/// [backdropOffset] from the panel's top-right corner, clipped by the
/// sheet frame (the source sheet's corner arcs).
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.subtitleLeading,
    this.backdrop,
    this.backdropOffset = Offset.zero,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? subtitleLeading;
  final Widget? backdrop;

  /// Where the backdrop's top-right corner lands relative to the panel's:
  /// negative x = past the right edge, negative y = above the top.
  final Offset backdropOffset;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final handle = theme.style.sheetHandleSize;
    final subtitleText = Text(subtitle, style: theme.type.mono(size: 12, color: t.textDim));
    final leading = subtitleLeading;
    final content = Padding(
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
            child: leading == null
                ? subtitleText
                : Row(children: [leading, const SizedBox(width: 10), Flexible(child: subtitleText)]),
          ),
          Flexible(child: SingleChildScrollView(child: child)),
        ],
      ),
    );
    final backdrop = this.backdrop;
    if (backdrop == null) return content;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(top: backdropOffset.dy, right: backdropOffset.dx, child: backdrop),
        content,
      ],
    );
  }
}
