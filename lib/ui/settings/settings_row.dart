import 'package:flutter/widgets.dart';

import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../widgets/check_mark.dart';

/// Inline settings row: label (+ description) on the left, optional
/// trailing value and chevron on the right. Tappable when [onTap] is set
/// (iOS: surface-2 press tint as the mockup; Android: the ripple — the
/// mockup shows no Android press feedback, used anyway for consistency
/// with every other row in the app).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.description,
    this.trailing,
    this.trailingKey,
    this.chevron = false,
    this.onTap,
  });

  final String label;
  final String? description;
  final String? trailing;
  final Key? trailingKey;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    Widget content(bool pressed) => Container(
      color: pressed && theme.style.isCupertino ? t.surface2 : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(child: SettingsRowHeading(label: label, description: description)),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Text(trailing!, key: trailingKey, style: theme.type.mono(size: 13, color: t.textDim), softWrap: false),
          ],
          if (chevron) ...[
            const SizedBox(width: 10),
            const ChevronMark(),
          ],
        ],
      ),
    );
    if (onTap == null) return content(false);
    return AdaptivePressable(
      onTap: onTap,
      borderRadius: BorderRadius.zero,
      pressedScale: 1,
      builder: (context, pressed) => content(pressed),
    );
  }
}

/// Label 14.5/600 + optional description 12 mono `textDim` (line-height
/// 1.4; v26 moved it up from faint — it carries real information).
class SettingsRowHeading extends StatelessWidget {
  const SettingsRowHeading({super.key, required this.label, this.description});

  final String label;
  final String? description;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.type.body(size: 14.5, weight: FontWeight.w600, color: t.text)),
        if (description != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(description!, style: theme.type.mono(size: 12, height: 1.4, color: t.textDim)),
          ),
      ],
    );
  }
}

/// Stacked settings row: heading on top, full-width control underneath
/// (the mockup's `.settings-row-stack`: at phone width there is no room
/// for a two-line description next to a segmented control or stepper).
class SettingsStackedRow extends StatelessWidget {
  const SettingsStackedRow({
    super.key,
    required this.label,
    this.description,
    required this.child,
    this.gap = 12,
  });

  final String label;
  final String? description;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsRowHeading(label: label, description: description),
          SizedBox(height: gap),
          child,
        ],
      ),
    );
  }
}
