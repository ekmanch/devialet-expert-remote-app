import 'package:flutter/widgets.dart';

import '../../domain/control_view_state.dart';
import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../widgets/check_mark.dart';
import 'control_keys.dart';
import 'source_glyph.dart';
import 'source_glyphs.dart';

/// Closed source row: glyph chip, name (15/600 like the amp name — v36
/// had 18, shrunk on the owner's 2026-09-23 mockup update because it drew
/// disproportionate attention), painted caret. No "Active source" eyebrow
/// since v36 — the SOURCE section header already says it. Placeholder
/// "No source" when nothing is selected (TODO 2.0.9).
class SourceTrigger extends StatelessWidget {
  const SourceTrigger({super.key, required this.state, required this.onTap});

  final ControlViewState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final source = state.hasAmp ? state.activeSource : null;
    return AdaptivePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      pressedScale: 0.98,
      pressedOpacity: 0.85,
      builder: (context, pressed) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.divider),
          borderRadius: BorderRadius.circular(16),
          boxShadow: t.cardShadow,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 34,
              child: Center(child: SourceGlyph(name: source?.name, size: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                source == null ? 'No source' : sourceDisplayName(source.name),
                key: ControlKeys.sourceName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.type.body(size: 15, weight: FontWeight.w600, color: t.text),
              ),
            ),
            const SizedBox(width: 12),
            const ChevronMark(),
          ],
        ),
      ),
    );
  }
}
