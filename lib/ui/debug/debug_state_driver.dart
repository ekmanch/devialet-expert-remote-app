import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/ui_variant.dart';
import '../../domain/control_view_state.dart';
import '../control/control_keys.dart';
import '../platform/adaptive_page_route.dart';
import '../theme/app_theme.dart';
import 'debug_network_screen.dart';
import 'simulated_amp.dart';

/// Debug-only, visible (not a hidden gesture — TODO 2.0.12) bar under the
/// Control column: drives the [SimulatedAmp] through every scenario so each
/// visual state can be eyeballed on the Galaxy S25 without an amp, and
/// keeps the Task 1 network test screen reachable. Renders nothing in
/// release builds.
class DebugStateDriver extends ConsumerWidget {
  const DebugStateDriver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!kDebugMode) return const SizedBox.shrink();
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final scenario = ref.watch(simulatedAmpProvider);
    final sim = ref.read(simulatedAmpProvider.notifier);
    final variant = ref.watch(uiVariantProvider);
    final mono = theme.type.mono(size: 11, letterSpacingEm: 0.04, color: t.textDim);

    Widget chip(Key key, String text, VoidCallback onTap) {
      return GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.divider),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(text, style: mono.copyWith(color: t.text)),
        ),
      );
    }

    return Container(
      key: ControlKeys.debugBar,
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: t.warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          chip(ControlKeys.debugPrev, '‹', () => sim.cycle(step: -1)),
          Expanded(
            child: Text(
              'SIM · ${sim.isActive ? scenario.label : 'off'} · ${variant.name}',
              textAlign: TextAlign.center,
              style: mono,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          chip(ControlKeys.debugNext, '›', () => sim.cycle()),
          const SizedBox(width: 8),
          chip(ControlKeys.debugNet, 'Net', () {
            Navigator.of(context).push(
              adaptivePageRoute<void>(context, (_) => DebugNetworkScreen(variant: variant)),
            );
          }),
        ],
      ),
    );
  }
}
