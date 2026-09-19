import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/ui_variant.dart';

/// Android wordmark-over-title vs iOS eyebrow-over-large-title.
enum HeaderKind { wordmark, eyebrow }

/// The per-variant *numbers and choices* from the mockups' CSS, derived
/// from [uiVariantProvider] so they stay overridable. Shared widgets read
/// these through `AppTheme.of(context).style`; only the adaptive
/// primitives in `lib/ui/platform/` branch on [isCupertino].
@immutable
class PlatformStyle {
  const PlatformStyle({
    required this.variant,
    required this.sidePadding,
    required this.contentTopPadding,
    required this.contentBottomPadding,
    required this.headerKind,
    required this.sheetHandleSize,
    required this.sheetTopRadius,
    required this.frostedSheets,
    required this.emptyStateTileSize,
    required this.emptyStateTileRadius,
  });

  factory PlatformStyle.forVariant(UiVariant variant) => switch (variant) {
    UiVariant.android => const PlatformStyle(
      variant: UiVariant.android,
      sidePadding: 22,
      contentTopPadding: 6,
      contentBottomPadding: 28,
      headerKind: HeaderKind.wordmark,
      sheetHandleSize: Size(36, 4),
      sheetTopRadius: 24,
      frostedSheets: false,
      emptyStateTileSize: 52,
      emptyStateTileRadius: 16,
    ),
    UiVariant.ios => const PlatformStyle(
      variant: UiVariant.ios,
      sidePadding: 20,
      contentTopPadding: 4,
      contentBottomPadding: 26,
      headerKind: HeaderKind.eyebrow,
      sheetHandleSize: Size(36, 5),
      sheetTopRadius: 20,
      frostedSheets: true,
      emptyStateTileSize: 44,
      emptyStateTileRadius: 14,
    ),
  };

  final UiVariant variant;
  final double sidePadding;
  final double contentTopPadding;
  final double contentBottomPadding;
  final HeaderKind headerKind;
  final Size sheetHandleSize;
  final double sheetTopRadius;
  final bool frostedSheets;
  final double emptyStateTileSize;
  final double emptyStateTileRadius;

  bool get isCupertino => variant == UiVariant.ios;

  @override
  bool operator ==(Object other) => other is PlatformStyle && other.variant == variant;

  @override
  int get hashCode => variant.hashCode;
}

final platformStyleProvider = Provider<PlatformStyle>(
  (ref) => PlatformStyle.forVariant(ref.watch(uiVariantProvider)),
);
