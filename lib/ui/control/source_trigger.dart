import 'package:flutter/widgets.dart';

import '../../domain/control_view_state.dart';
import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import 'control_keys.dart';
import 'source_glyphs.dart';

/// Closed source row: glyph chip, "Active source" eyebrow, name (elided),
/// caret. Placeholder "No source" when nothing is selected (TODO 2.0.9).
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
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
              child: Text(
                sourceGlyphFor(source?.name),
                style: TextStyle(fontSize: 16, color: t.copperBright, height: 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'Active source',
                      style: theme.type.mono(size: 12, letterSpacingEm: 0.04, color: t.textFaint),
                    ),
                  ),
                  Text(
                    source?.name ?? 'No source',
                    key: ControlKeys.sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.type.body(size: 15, weight: FontWeight.w600, color: t.text),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('›', style: theme.type.body(size: 15, color: t.textFaint)),
          ],
        ),
      ),
    );
  }
}
