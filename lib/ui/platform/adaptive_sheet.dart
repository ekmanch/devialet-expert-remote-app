import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../config/window_class.dart';
import '../control/control_layout.dart';
import '../theme/app_theme.dart';

/// Bottom sheet per variant: Material modal bottom sheet with the
/// mockup's opaque gradient panel on Android; a Cupertino modal popup
/// with a frosted (blurred, tinted) panel on iOS. Both cap the panel at
/// 72 % of the window height and, outside the compact width class, at the
/// interim column width so it doesn't span a tablet (TODO 2.0.0).
///
/// The sheet lives in a `Navigator` route, so its state (manual-IP draft,
/// list/entry toggle) survives a window-class change under it (TODO 2.0.1).
Future<T?> showAdaptiveSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  final theme = AppTheme.of(context);
  final tokens = theme.tokens;
  if (theme.style.isCupertino) {
    return showCupertinoModalPopup<T>(
      context: context,
      barrierColor: tokens.scrimCupertino,
      builder: (ctx) => _SheetFrame(child: builder(ctx)),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: tokens.scrimMaterial,
    isScrollControlled: true,
    useSafeArea: true,
    // The frame does its own width/height capping and clipping.
    constraints: const BoxConstraints(maxWidth: double.infinity),
    builder: (ctx) => _SheetFrame(child: builder(ctx)),
  );
}

class _SheetFrame extends StatelessWidget {
  const _SheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final tokens = theme.tokens;
    final style = theme.style;
    final size = MediaQuery.sizeOf(context);
    final windowClass = WindowClassScope.of(context);
    final maxWidth = windowClass.width == WindowWidthClass.compact
        ? double.infinity
        : kInterimColumnMaxWidth + 2 * style.sidePadding;
    final radius = BorderRadius.vertical(top: Radius.circular(style.sheetTopRadius));

    Widget panel = Container(
      decoration: BoxDecoration(
        color: style.frostedSheets ? tokens.sheetTint : null,
        gradient: style.frostedSheets
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tokens.sheetBg1, tokens.sheetBg2],
              ),
        border: Border(top: BorderSide(color: tokens.divider)),
        boxShadow: const [BoxShadow(color: Color(0x80000000), offset: Offset(0, -12), blurRadius: 40)],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom),
        child: child,
      ),
    );
    if (style.frostedSheets) {
      panel = BackdropFilter(filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: panel);
    }

    // heightFactor 1: the route's widget is only as tall as the panel, so a
    // tap above it reaches the dismissing barrier rather than the sheet's
    // own drag region.
    return Align(
      alignment: Alignment.bottomCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: size.height * 0.72),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(type: MaterialType.transparency, child: panel),
        ),
      ),
    );
  }
}
