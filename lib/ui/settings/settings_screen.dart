import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_info.dart';
import '../../config/window_class.dart';
import '../../domain/settings/app_settings.dart';
import '../../domain/settings/hydrated_settings.dart';
import '../../domain/settings/settings_owner.dart';
import '../control/control_layout.dart';
import '../platform/adaptive_pressable.dart';
import '../platform/adaptive_sheet.dart';
import '../platform/platform_style.dart';
import '../theme/app_theme.dart';
import '../widgets/section_label.dart';
import 'db_stepper.dart';
import 'segmented_control.dart';
import 'settings_group.dart';
import 'settings_keys.dart';
import 'settings_row.dart';
import 'theme_sheet.dart';
import 'url_opener.dart';

/// The Settings screen (Task 3.4.x): per-variant scaffold and top bar
/// around [SettingsBody]. Settings are **effective immediately** — each
/// control emits an intent and the settings owner persists it (the
/// Android/iOS convention; the KDE widget's Apply button follows Plasma's
/// config-dialog convention, and the two deliberately differ).
/// Task 3.11.x hosts [SettingsBody] in a side pane on expanded widths.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final style = theme.style;
    final widthClass = WindowClassScope.of(context).width;

    final body = SafeArea(
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widthClass == WindowWidthClass.compact ? double.infinity : kInterimColumnMaxWidth,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                style.sidePadding,
                style.contentTopPadding,
                style.sidePadding,
                style.contentBottomPadding,
              ),
              child: Column(
                key: SettingsUiKeys.screen,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [_SettingsTopBar(), SettingsBody()],
              ),
            ),
          ),
        ),
      ),
    );

    if (style.isCupertino) {
      return CupertinoPageScaffold(
        backgroundColor: t.bg,
        child: Material(type: MaterialType.transparency, child: body),
      );
    }
    return Scaffold(backgroundColor: t.bg, body: body);
  }
}

/// Android: 38×38 icon button "‹" + left title 22/600. iOS: "‹ Remote"
/// text back control in copper (plain text colour in light — gold is
/// reserved for the wordmark) + centred title 16/600.
class _SettingsTopBar extends StatelessWidget {
  const _SettingsTopBar();

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    void back() => Navigator.of(context).maybePop();

    if (theme.style.headerKind == HeaderKind.eyebrow) {
      final color = t.isDark ? t.copperBright : t.text;
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 6),
        child: SizedBox(
          height: 30,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 0,
                child: AdaptivePressable(
                  key: SettingsUiKeys.backButton,
                  onTap: back,
                  borderRadius: BorderRadius.circular(8),
                  pressedScale: 1,
                  pressedOpacity: 0.6,
                  builder: (context, pressed) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('\u2039', style: theme.type.body(size: 20, color: color, height: 1)),
                      const SizedBox(width: 1),
                      Text('Remote', style: theme.type.body(size: 16, weight: FontWeight.w500, color: color)),
                    ],
                  ),
                ),
              ),
              Text('Settings', key: SettingsUiKeys.title, style: theme.type.display(size: 16, color: t.text)),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 4),
      child: Row(
        children: [
          AdaptivePressable(
            key: SettingsUiKeys.backButton,
            onTap: back,
            borderRadius: BorderRadius.circular(12),
            pressedScale: 0.92,
            pressedOpacity: 0.8,
            builder: (context, pressed) => Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.divider),
                borderRadius: BorderRadius.circular(12),
                boxShadow: t.cardShadow,
              ),
              child: Text('\u2039', style: theme.type.display(size: 18, color: t.textDim, height: 1)),
            ),
          ),
          const SizedBox(width: 12),
          Text('Settings', key: SettingsUiKeys.title, style: theme.type.display(size: 22, color: t.text)),
        ],
      ),
    );
  }
}

/// Everything below the top bar. Reads [settingsProvider] and writes
/// through its intents; persistence problems are shown at the top
/// (checklist item 26: a broken store must look broken).
class SettingsBody extends ConsumerWidget {
  const SettingsBody({super.key});

  static const String footerText = 'Devialet Expert Pro Remote';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final storeUnavailable = ref.watch(hydratedSettingsProvider).storeUnavailable;
    final writeError = ref.watch(settingsWriteErrorProvider);
    final gap = VolumeLimitRules.minGapDb.round();

    final note = storeUnavailable
        ? "Settings can't be saved on this device \u2014 changes apply until the app closes"
        : writeError != null
        ? "A setting couldn't be saved \u2014 it applies until the app closes"
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note != null)
          Container(
            key: SettingsUiKeys.persistenceNote,
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: t.warningBright),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(note, style: theme.type.mono(size: 12, height: 1.4, color: t.warningBright)),
          ),
        const SectionLabel('Volume', first: true),
        SettingsGroup(
          children: [
            SettingsStackedRow(
              label: 'Volume Step Size',
              child: SegmentedControl<VolumeStepDb>(
                options: const [(VolumeStepDb.half, '0.5 dB'), (VolumeStepDb.one, '1 dB'), (VolumeStepDb.two, '2 dB')],
                value: s.stepDb,
                onChanged: n.setStepDb,
                keyFor: SettingsUiKeys.stepOption,
              ),
            ),
            SettingsStackedRow(
              label: 'Startup / Source-Switch Volume',
              description: 'Default volume on startup/ source switch',
              gap: 14,
              child: DbStepper(
                value: s.startupVolumeDb.round(),
                min: VolumeLimitRules.minDb.round(),
                max: VolumeLimitRules.maxDb.round(),
                onChanged: (v) => n.setStartupVolumeDb(v.toDouble()),
                keys: SettingsUiKeys.startupStepper,
              ),
            ),
          ],
        ),
        const SectionLabel('Volume Limits'),
        SettingsGroup(
          children: [
            SettingsStackedRow(
              label: 'Volume Floor',
              description: 'Lowest volume possible to set',
              gap: 14,
              child: DbStepper(
                value: s.floorDb.round(),
                min: VolumeLimitRules.minDb.round(),
                // The ceiling bounds the floor (1 dB gap); only the pressed value moves.
                max: s.ceilingDb.round() - gap,
                onChanged: (v) => n.setVolumeLimits(floorDb: v.toDouble()),
                keys: SettingsUiKeys.floorStepper,
              ),
            ),
            SettingsStackedRow(
              label: 'Volume Ceiling',
              description: 'Highest volume possible to set',
              gap: 14,
              child: DbStepper(
                value: s.ceilingDb.round(),
                min: s.floorDb.round() + gap,
                max: VolumeLimitRules.maxDb.round(),
                onChanged: (v) => n.setVolumeLimits(ceilingDb: v.toDouble()),
                keys: SettingsUiKeys.ceilingStepper,
              ),
            ),
          ],
        ),
        const SectionLabel('Appearance'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: SettingsUiKeys.themeRow,
              label: 'Theme',
              trailing: switch (s.themeMode) {
                AppThemeMode.system => 'System',
                AppThemeMode.dark => 'Dark',
                AppThemeMode.light => 'Light',
              },
              trailingKey: SettingsUiKeys.themeTrailing,
              chevron: true,
              onTap: () => showAdaptiveSheet<void>(context, builder: (_) => const ThemeSheet()),
            ),
          ],
        ),
        const SectionLabel('About'),
        SettingsGroup(
          children: [
            SettingsRow(
              key: SettingsUiKeys.versionRow,
              label: 'Version',
              trailing: kAppVersion,
              trailingKey: SettingsUiKeys.versionValue,
            ),
            SettingsRow(
              key: SettingsUiKeys.githubRow,
              label: 'View on GitHub',
              chevron: true,
              onTap: () async {
                try {
                  await ref.read(urlOpenerProvider)(Uri.parse(kGitHubUrl));
                } catch (_) {
                  // No browser available: nothing else to do on this screen.
                }
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 22),
          child: Text(
            footerText,
            key: SettingsUiKeys.footer,
            textAlign: TextAlign.center,
            style: theme.type.mono(size: 11, letterSpacingEm: 0.02, color: t.textFaint),
          ),
        ),
      ],
    );
  }
}
