import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/window_class.dart';
import '../../domain/amp_state_owner.dart';
import '../../domain/control_view_state.dart';
import '../platform/adaptive_page_route.dart';
import '../platform/adaptive_sheet.dart';
import '../settings/settings_screen.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../widgets/dimmed_group.dart';
import '../widgets/section_label.dart';
import 'amp_sheet.dart';
import 'control_fill_layout.dart';
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
///
/// Sheets (Task 3.8.2 / 3.0.6): the owner's `visibleSheet` is the truth.
/// The triggers call `openSheet`; this screen pushes the matching modal
/// route when the slot leaves `none`, and the route's completion future —
/// which fires on **every** pop, whatever caused it (hardware back,
/// predictive back, a barrier tap, the Material drag-down, a row's own
/// `Navigator.pop`, the sheet popping itself) — writes `none` back through
/// `closeSheet`. That one `whenComplete` is the structural guarantee
/// (checklist 28); its boundary: a sheet pushed by any other function
/// would not be covered. A sheet pops *itself* when the slot stops naming
/// it (`ref.listen` inside each sheet), so an owner-side close (the power
/// edge) or a slot swap needs no route handle here. On compact width the
/// sheet is modal, so "reset when the screen is left" reduces to
/// [dispose]; 3.11.x revisits this when sheets become panes.
class ControlScreen extends ConsumerStatefulWidget {
  const ControlScreen({super.key});

  @override
  ConsumerState<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends ConsumerState<ControlScreen> {
  double? _dragDb;
  final GlobalKey<VolumeDialState> _dialKey = GlobalKey<VolumeDialState>();

  /// The sheet whose route this screen last pushed and has not seen
  /// complete. Bookkeeping only — the owner's slot is the truth.
  SheetKind _pushedKind = SheetKind.none;
  late final AmpStateOwner _owner;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(ampStateProvider.notifier);
    ref.listenManual(controlViewStateProvider.select((s) => s.visibleSheet), (_, next) => _reconcileSheet(next));
  }

  @override
  void dispose() {
    // "Screen left": the slot resets; the route (if any) is torn down with
    // the navigator and its completion no-ops on the already-none slot.
    _owner.closeSheet();
    super.dispose();
  }

  void _openAmpSheet() => _owner.openSheet(SheetKind.amp);

  void _openSourceSheet() => _owner.openSheet(SheetKind.source);

  /// Slot → route. `none` needs nothing here (the sheet pops itself); a
  /// kind this screen already pushed needs nothing; a new kind is pushed.
  /// Re-entrancy: owner → none: the sheet pops → its future completes →
  /// `closeSheet(kind)` no-ops. User pop: the future → `closeSheet(kind)`
  /// → none → the sheet's own listener finds its route no longer current
  /// and does nothing. kind → kind: the old sheet pops itself (its
  /// completion no-ops because the slot names the new kind) and the new
  /// one is pushed here.
  void _reconcileSheet(SheetKind next) {
    if (next == SheetKind.none || next == _pushedKind) return;
    final kind = next;
    _pushedKind = kind;
    final owner = _owner; // not `ref`: the completion can arrive after dispose
    showAdaptiveSheet<void>(
      context,
      builder: (_) => kind == SheetKind.amp ? const AmpSheet() : const SourceSheet(),
    ).whenComplete(() {
      if (_pushedKind == kind) _pushedKind = SheetKind.none;
      owner.closeSheet(kind);
    });
  }

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

    // A drag interrupted by the group going inert (the amp went Off or
    // silent under the finger) ends here, uncommitted: the dial's
    // callbacks are nulled while disabled, so its release never reaches
    // us (Task 3.6.4). A plain field write — this *is* the build.
    if (!state.volumeGroupEnabled) _dragDb = null;
    // `null` == no reading (no amp, Task 3.9.4): the dial rests and the
    // readout is a dash — nothing here ever substitutes a number.
    final shownDb = _dragDb ?? state.volumeDb;
    final String valueText;
    if (!state.hasAmp || shownDb == null) {
      valueText = '—';
    } else if (state.isMuted && _dragDb == null) {
      // The readout follows the finger even on a muted amp (KDE's label is
      // bound to the slider); "Muted" outside a drag derives from the
      // masked state, never from the button (Task 3.7.2).
      valueText = 'Muted';
    } else {
      valueText = formatDb(shownDb);
    }

    // The dial slot is laid out by FilledControlLayout at the fitted size;
    // everything that scales with it (ring geometry, readout type) reads
    // that size here, in layout, from the tight constraints.
    final dial = DimmedGroup(
      key: ControlKeys.dialWrap,
      dimmed: !state.volumeGroupEnabled,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          final k = size / kControlDialBase;
          return VolumeDial(
            key: _dialKey,
            size: size,
            trackRadius: 96 * k,
            trackWidth: 10 * k,
            innerHitSlop: 28 * k,
            minDb: state.floorDb,
            maxDb: state.ceilingDb,
            stepDb: state.stepDb,
            valueDb: shownDb,
            enabled: state.volumeGroupEnabled,
            showArc: state.hasAmp,
            onChanged: (db) => setState(() => _dragDb = db),
            onChangeEnd: (db) {
              notifier.setVolumeDb(db);
              setState(() => _dragDb = null);
            },
            child: DialReadout(
              scale: k,
              valueText: valueText,
              unitVisible: state.hasAmp && (!state.isMuted || _dragDb != null),
              sourceLabel: state.hasAmp ? (state.activeSource?.name ?? 'No source') : 'No source',
            ),
          );
        },
      ),
    );

    final column = FilledControlLayout(
      key: ControlKeys.column,
      top: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ControlHeader(onSettingsTap: _openSettings),
          DeviceCard(state: state, onTap: _openAmpSheet, onPower: notifier.togglePower),
          // Stays "Volume" on the alternate layout: power is on the card,
          // so this block is only volume + mute (mainline v48 says "Controls").
          const SectionLabel('Volume', first: true, accent: true, top: kControlSectionTopFirst),
        ],
      ),
      dial: dial,
      roundRow: DimmedGroup(
        dimmed: !state.volumeGroupEnabled,
        child: VolumeButtons(
          key: ControlKeys.roundRow,
          enabled: state.volumeGroupEnabled,
          onMinus: () => notifier.stepVolume(-1),
          onPlus: () => notifier.stepVolume(1),
          isMuted: state.isMuted,
          onMute: notifier.toggleMute,
        ),
      ),
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('Source', key: ControlKeys.sourceLabel, accent: true, top: kControlSectionTop),
          DimmedGroup(
            key: ControlKeys.sourceTrigger,
            dimmed: !state.volumeGroupEnabled,
            opacity: state.hasAmp ? 0.4 : 0.5,
            blockTaps: state.hasAmp,
            child: SourceTrigger(state: state, onTap: _openSourceSheet),
          ),
        ],
      ),
    );

    // The viewport height is the column's *minimum* (fill), never its
    // maximum (scroll). `maintainBottomViewPadding` + the scaffolds'
    // `resizeToAvoidBottomInset: false` below: the keyboard under the amp
    // sheet's manual-IP field must not re-fit the dial behind the scrim;
    // the sheet route handles its own inset.
    final body = SafeArea(
      maintainBottomViewPadding: true,
      child: LayoutBuilder(
        builder: (context, viewport) {
          final minHeight = viewport.maxHeight.isFinite
              ? math.max(0.0, viewport.maxHeight - style.contentTopPadding - style.contentBottomPadding)
              : 0.0;
          return SingleChildScrollView(
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
                  child: ConstrainedBox(constraints: BoxConstraints(minHeight: minHeight), child: column),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (style.isCupertino) {
      return CupertinoPageScaffold(
        backgroundColor: t.bg,
        resizeToAvoidBottomInset: false,
        child: Material(type: MaterialType.transparency, child: body),
      );
    }
    return Scaffold(backgroundColor: t.bg, resizeToAvoidBottomInset: false, body: body);
  }
}
