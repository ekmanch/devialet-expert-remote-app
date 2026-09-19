import 'package:flutter/widgets.dart';

import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import 'control_keys.dart';

/// VOL − / + (tap only; press-and-hold repeat is Task 3.6.1).
class VolumeButtons extends StatelessWidget {
  const VolumeButtons({super.key, required this.onMinus, required this.onPlus});

  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        children: [
          Expanded(child: _VolButton(key: ControlKeys.volMinus, glyph: '−', onTap: onMinus)),
          const SizedBox(width: 14),
          Expanded(child: _VolButton(key: ControlKeys.volPlus, glyph: '+', onTap: onPlus)),
        ],
      ),
    );
  }
}

class _VolButton extends StatelessWidget {
  const _VolButton({super.key, required this.glyph, required this.onTap});

  final String glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return AdaptivePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      pressedScale: 0.94,
      builder: (context, pressed) => Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed && theme.style.isCupertino ? t.surface2 : t.surface,
          border: Border.all(color: t.divider),
          borderRadius: BorderRadius.circular(16),
          boxShadow: t.cardShadow,
        ),
        child: Text(glyph, style: theme.type.display(size: 20, color: t.text)),
      ),
    );
  }
}
