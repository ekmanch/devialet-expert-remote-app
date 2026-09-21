import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/window_class.dart';
import '../../domain/amp_state_owner.dart';
import '../debug/debug_state_driver.dart';
import '../platform/adaptive_page_route.dart';
import '../platform/adaptive_sheet.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../widgets/dimmed_group.dart';
import '../widgets/section_label.dart';
import 'action_row.dart';
import 'amp_sheet.dart';
import 'control_footer.dart';
import 'control_header.dart';
import 'control_keys.dart';
import 'control_layout.dart';
import 'device_card.dart';
import 'source_sheet.dart';
import 'source_trigger.dart';
import 'volume_buttons.dart';
import 'volume_dial.dart';

/// The Control screen (Task 2.0.x). One column of widgets shared by both
/// UI variants; the scaffold, press feedback and sheets are the only
/// per-variant parts. Width class only changes the constraint around the
/// column (interim centred column outside compact — TODO 2.0.0); Task
/// 3.11.1 replaces that constraint with a two-pane layout.
///
/// Owns the live drag value so the readout follows the finger and a
/// window-class change mid-drag keeps it (TODO 2.0.1 / 2.0.4).
class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  double? _dragDb;
  final GlobalKey<VolumeDialState> _dialKey = GlobalKey<VolumeDialState>();

  void _openAmpSheet() => showAdaptiveSheet<void>(context, builder: (_) => const AmpSheet());

  void _openSourceSheet() => showAdaptiveSheet<void>(context, builder: (_) => const SourceSheet());

  void _openSettings() =>
      Navigator.of(context).push(adaptivePageRoute<void>(context, (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final style = theme.style;
    final state = ref.watch(controlViewStateProvider);
    final notifier = ref.read(ampStateProvider.notifier);
    final widthClass = WindowClassScope.of(context).width;

    final shownDb = _dragDb ?? state.volumeDb;
    final String valueText;
    if (!state.hasAmp) {
      valueText = '—';
    } else if (state.isMuted) {
      valueText = 'Muted';
    } else {
      valueText = formatDb(shownDb);
    }

    final column = Column(
      key: ControlKeys.column,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ControlHeader(onSettingsTap: _openSettings),
        DeviceCard(state: state, onTap: _openAmpSheet),
        const SectionLabel('Volume', first: true),
        DimmedGroup(
          key: ControlKeys.dialWrap,
          dimmed: !state.volumeGroupEnabled,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: VolumeDial(
                  key: _dialKey,
                  minDb: state.floorDb,
                  maxDb: state.ceilingDb,
                  valueDb: shownDb,
                  enabled: state.volumeGroupEnabled,
                  showArc: state.hasAmp,
                  onChanged: (db) => setState(() => _dragDb = db),
                  onChangeEnd: (db) {
                    notifier.setVolumeDb(db);
                    setState(() => _dragDb = null);
                  },
                  child: DialReadout(
                    valueText: valueText,
                    unitVisible: state.hasAmp && !state.isMuted,
                    sourceLabel: state.hasAmp ? (state.activeSource?.name ?? 'No source') : 'No source',
                  ),
                ),
              ),
              VolumeButtons(
                enabled: state.volumeGroupEnabled,
                onMinus: () => notifier.stepVolume(-1),
                onPlus: () => notifier.stepVolume(1),
              ),
            ],
          ),
        ),
        DimmedGroup(
          key: ControlKeys.actionRow,
          dimmed: !state.hasAmp,
          child: ActionRow(state: state, onMute: notifier.toggleMute, onPower: notifier.togglePower),
        ),
        const SectionLabel('Source'),
        DimmedGroup(
          key: ControlKeys.sourceTrigger,
          dimmed: !state.volumeGroupEnabled,
          opacity: state.hasAmp ? 0.4 : 0.5,
          blockTaps: state.hasAmp,
          child: SourceTrigger(state: state, onTap: _openSourceSheet),
        ),
        ControlFooter(state: state),
        const DebugStateDriver(),
      ],
    );

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
              child: column,
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
