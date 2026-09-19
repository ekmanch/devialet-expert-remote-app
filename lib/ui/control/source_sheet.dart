import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/control_view_state_provider.dart';
import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../widgets/sheet_scaffold.dart';
import 'source_glyphs.dart';

/// "Select source": one row per enabled source, active row in copper with
/// a check; empty state when the amp has none / no amp (TODO 2.0.9).
class SourceSheet extends ConsumerWidget {
  const SourceSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final state = ref.watch(controlViewStateProvider);
    final notifier = ref.read(controlViewStateProvider.notifier);

    return SheetScaffold(
      title: 'Select source',
      subtitle: state.hasAmp ? state.selectedAmp!.displayName : 'No amplifier connected',
      child: state.sources.isEmpty
          ? const _SourceEmptyState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final source in state.sources)
                  AdaptivePressable(
                    onTap: () {
                      notifier.selectSource(source.index);
                      Navigator.of(context).pop();
                    },
                    borderRadius: BorderRadius.circular(12),
                    builder: (context, pressed) {
                      final selected = source.index == state.activeSourceIndex;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                        decoration: BoxDecoration(
                          color: pressed ? t.surface2 : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selected && t.isDark ? t.accentTint(0.18) : null,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                sourceGlyphFor(source.name),
                                style: TextStyle(fontSize: 15, color: t.copperBright, height: 1),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                source.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.type.body(size: 15, color: selected ? t.copperBright : t.text),
                              ),
                            ),
                            Opacity(
                              opacity: selected ? 1 : 0,
                              child: Text('✓', style: TextStyle(fontSize: 14, color: t.copperBright)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
    );
  }
}

class _SourceEmptyState extends StatelessWidget {
  const _SourceEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final ios = theme.style.isCupertino;
    return Padding(
      padding: ios ? const EdgeInsets.fromLTRB(20, 8, 20, 4) : const EdgeInsets.fromLTRB(20, 48, 20, 24),
      child: Column(
        children: [
          Container(
            width: theme.style.emptyStateTileSize,
            height: theme.style.emptyStateTileSize,
            alignment: Alignment.center,
            margin: EdgeInsets.only(bottom: ios ? 12 : 16),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.divider),
              borderRadius: BorderRadius.circular(theme.style.emptyStateTileRadius),
            ),
            child: Text('◇', style: TextStyle(fontSize: ios ? 18 : 20, color: t.textFaint, height: 1)),
          ),
          Text('No sources available', style: theme.type.display(size: ios ? 14 : 15, color: t.textDim)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ios ? 230 : 240),
            child: Text(
              'Connect to an amplifier to see its sources.',
              textAlign: TextAlign.center,
              style: theme.type.body(size: ios ? 12 : 12.5, height: 1.5, color: t.textFaint),
            ),
          ),
        ],
      ),
    );
  }
}
