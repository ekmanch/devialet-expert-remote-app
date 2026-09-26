import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'check_mark.dart';
import 'header_icon_button.dart';

/// Handle + title + subtitle + scrollable body, per the mockups' sheet
/// panel (padding 10 18 20; handle 36×4 Android / 36×5 iOS; title 17/600
/// display; subtitle 12 mono, `textDim` since v26 — it carries real
/// information). [subtitleLeading] sits before the subtitle (the amp
/// picker's listening arcs); [backdrop] paints behind everything at
/// [backdropOffset] from the panel's top-right corner, clipped by the
/// sheet frame (the source sheet's corner arcs). [onBack] puts a bare
/// back chevron beside the title (a 44 dp [HeaderIconButton] overhanging
/// the content edge by 12 like the Android back arrow) and indents the
/// subtitle under the title — the amp picker's manual-entry view.
/// [footer] sits *below* the scrolling body, always visible (v45: the amp
/// list scrolls, "Enter IP Manually" is pinned — the escape hatch never
/// needs scrolling); [bodyFade] fades the body's last dp so a cut-off row
/// reads as "more below" (the mockup's 14 px mask on `.sheet-list`).
class SheetScaffold extends StatelessWidget {
  const SheetScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.subtitleLeading,
    this.backdrop,
    this.backdropOffset = Offset.zero,
    this.onBack,
    this.backKey,
    this.footer,
    this.bodyFade,
  });

  final VoidCallback? onBack;
  final Key? backKey;
  final Widget? footer;
  final double? bodyFade;

  /// The back button's visible width inside the content edge
  /// (44 − 12 overhang); the title and subtitle start after it.
  static const double backSlot = HeaderIconButton.size - 12;

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? subtitleLeading;
  final Widget? backdrop;

  /// Where the backdrop's top-right corner lands relative to the panel's:
  /// negative x = past the right edge, negative y = above the top.
  final Offset backdropOffset;

  /// `mask-image: linear-gradient(to bottom, #000 calc(100% − fade), transparent)`.
  Widget _fadeBottom(Widget body) {
    final fade = bodyFade;
    if (fade == null) return body;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0xFF000000), Color(0xFF000000), Color(0x00000000)],
        stops: [0, bounds.height <= fade ? 0 : 1 - fade / bounds.height, 1],
      ).createShader(Offset.zero & bounds.size),
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final handle = theme.style.sheetHandleSize;
    final subtitleText = Text(subtitle, style: theme.type.mono(size: 12, color: t.textDim));
    final leading = subtitleLeading;
    final onBack = this.onBack;
    final Widget titleText = Text(title, style: theme.type.display(size: 17, color: t.text));
    final Widget header = onBack == null
        ? titleText
        : Row(
            children: [
              HeaderIconButton(
                key: backKey,
                onTap: onBack,
                overhang: -12,
                child: Transform.flip(flipX: true, child: ChevronMark(size: 22, color: t.textDim)),
              ),
              Expanded(child: titleText),
            ],
          );
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
              // The 44 dp back row centres the title 12 lower than the bare
              // title would sit, so its margin gives that back.
              margin: EdgeInsets.only(top: theme.style.isCupertino ? 4 : 2, bottom: onBack == null ? 14 : 2),
              decoration: BoxDecoration(
                color: t.isDark ? t.surface3 : t.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          header,
          Padding(
            padding: EdgeInsets.only(top: 2, bottom: 14, left: onBack == null ? 0 : backSlot),
            child: leading == null
                ? subtitleText
                : Row(children: [leading, const SizedBox(width: 10), Flexible(child: subtitleText)]),
          ),
          Flexible(child: _fadeBottom(SingleChildScrollView(child: child))),
          ?footer,
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
