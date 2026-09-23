import 'package:flutter/widgets.dart';

import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';

/// The mockup's `.segmented`: a surface-3 track (r12, padding 3, gap 2)
/// of equal-width options; the selected one gets a `text`-coloured
/// outline and text (v28/v29: neutral, the accent lives in the section
/// headings) — outline only, no sliding pill. Weight 600: the mockup
/// declares 700 in dark, but JetBrains Mono is loaded up to 600 there as
/// here, so 600 is what it renders (checklist item 15).
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.keyFor,
  });

  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;
  final Key Function(T value)? keyFor;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface3,
        border: Border.all(color: t.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              child: AdaptivePressable(
                key: keyFor?.call(options[i].$1),
                onTap: () => onChanged(options[i].$1),
                borderRadius: BorderRadius.circular(9),
                pressedScale: 1,
                builder: (context, pressed) {
                  final selected = options[i].$1 == value;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: selected ? t.text : const Color(0x00000000)),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      options[i].$2,
                      style: theme.type.mono(
                        size: 13,
                        weight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? t.text : t.textDim,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
