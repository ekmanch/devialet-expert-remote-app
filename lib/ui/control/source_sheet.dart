import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/amp_state_owner.dart';
import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../widgets/arcs.dart';
import '../widgets/dimmed_group.dart';
import '../widgets/check_mark.dart';
import '../widgets/sheet_scaffold.dart';
import 'control_keys.dart';
import 'source_glyph.dart';
import 'source_glyphs.dart';

/// "Select source": one outlined card per enabled source (v36: 1.5 px
/// divider border, r16, 8 apart) with the glyph, the name, a mono "kind"
/// label and a check; the active card's border, name and check are
/// copper. Empty state when the amp has none / no amp (TODO 2.0.9).
/// Decorative arcs bleed off the panel's top-right corner.
///
/// The sheet watches the live view state, so if the amp goes Off / Booting
/// while it is open the rows dim to 0.4 and go inert **in place** — the
/// sheet stays open, keeps its text, and comes back live when the amp is
/// On again (Task 3.5.1, owner decision 2026-09-21; the "close sheets when
/// power leaves On" rule is Task 3.8.2). A *silent* amp already renders
/// the empty state because `sources` is empty (Task 3.0.8).
class SourceSheet extends ConsumerWidget {
  const SourceSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final state = ref.watch(controlViewStateProvider);
    final notifier = ref.read(ampStateProvider.notifier);

    return SheetScaffold(
      title: 'Select source',
      subtitle: state.hasAmp ? state.selectedAmp!.displayName : 'No amplifier connected',
      backdrop: const SheetArcs(),
      backdropOffset: SheetArcs.offset,
      child: state.sources.isEmpty
          ? const _SourceEmptyState()
          : DimmedGroup(
              key: ControlKeys.sourceRows,
              dimmed: !state.commandsAllowed,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, source) in state.sources.indexed) ...[
                    if (i > 0) const SizedBox(height: 8),
                    AdaptivePressable(
                      // Belt and braces with the group above: the row is
                      // inert by itself too (checklist item 6).
                      enabled: state.commandsAllowed,
                      onTap: () {
                        notifier.selectSource(source.index);
                        Navigator.of(context).pop();
                      },
                      borderRadius: BorderRadius.circular(16),
                      builder: (context, pressed) {
                        final selected = source.index == state.activeSourceIndex;
                        final kind = sourceKindFor(source.name);
                        return Container(
                          key: ControlKeys.sourceCard(source.index),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          decoration: BoxDecoration(
                            color: pressed ? t.surface2 : null,
                            border: Border.all(color: selected ? t.copperBright : t.divider, width: 1.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: Center(child: SourceGlyph(name: source.name, size: 15)),
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
                              if (kind != null) ...[
                                const SizedBox(width: 12),
                                Text(kind, style: theme.type.mono(size: 11, color: t.textFaint)),
                              ],
                              const SizedBox(width: 10),
                              Opacity(
                                opacity: selected ? 1 : 0,
                                child: const CheckMark(),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
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
            child: Text(
              '◇',
              style: TextStyle(fontSize: ios ? 18 : 20, color: t.textFaint, height: 1),
            ),
          ),
          Text(
            'No sources available',
            style: theme.type.display(size: ios ? 14 : 15, color: t.textDim),
          ),
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
