import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/settings/app_settings.dart';
import '../../domain/settings/settings_owner.dart';
import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../widgets/check_mark.dart';
import '../widgets/sheet_scaffold.dart';
import 'settings_keys.dart';
import 'theme_glyph.dart';

/// "Choose Theme": Follow System / Dark / Light. Applies at once through
/// the settings owner (the app root follows it) and closes after the
/// mockup's 180 ms.
class ThemeSheet extends ConsumerStatefulWidget {
  const ThemeSheet({super.key});

  static String labelFor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => 'Follow System',
    AppThemeMode.dark => 'Dark',
    AppThemeMode.light => 'Light',
  };

  @override
  ConsumerState<ThemeSheet> createState() => _ThemeSheetState();
}

class _ThemeSheetState extends ConsumerState<ThemeSheet> {
  Timer? _close;

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  void _choose(AppThemeMode mode) {
    ref.read(settingsProvider.notifier).setThemeMode(mode);
    _close?.cancel();
    _close = Timer(const Duration(milliseconds: 180), () {
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final current = ref.watch(settingsProvider.select((s) => s.themeMode));
    return SheetScaffold(
      title: 'Choose Theme',
      subtitle: 'Applies across the app',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final mode in AppThemeMode.values)
            AdaptivePressable(
              key: SettingsUiKeys.themeOption(mode),
              onTap: () => _choose(mode),
              borderRadius: BorderRadius.circular(12),
              builder: (context, pressed) {
                final selected = mode == current;
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
                        child: ThemeGlyph(mode: mode, size: 15),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          ThemeSheet.labelFor(mode),
                          style: theme.type.body(size: 15, color: selected ? t.copperBright : t.text),
                        ),
                      ),
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
      ),
    );
  }
}
