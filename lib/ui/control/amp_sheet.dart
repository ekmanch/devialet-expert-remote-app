import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/control_view_state.dart';
import '../../domain/amp_state_owner.dart';
import '../platform/adaptive_pressable.dart';
import '../platform/adaptive_text_field.dart';
import '../platform/sheet_self_pop.dart';
import '../theme/app_theme.dart';
import '../widgets/arcs.dart';
import '../widgets/check_mark.dart';
import '../widgets/sheet_scaffold.dart';
import 'control_keys.dart';
import 'device_card.dart';
import 'manual_entry_glyph.dart';

/// "Choose Amplifier" (TODO 2.0.3, Task 3.9.0 / v44, mainline v45–v47):
/// "None" first (italic, dashed dot, "Don't connect to any amplifier"),
/// divider, the responding amps (title `model ?? name ?? ip`, the IP
/// alone underneath — v47 dropped the friendly name and the "name
/// unresolved" marker; a row titled by its IP reads "Online"), then —
/// under a quiet "NOT RESPONDING" label — every amp known but silent
/// (hollow ring, dimmed, "Last seen …"; the chosen one keeps its check
/// with a pulsing accent ring and "Reconnecting…"), and the never-heard
/// selection ("Connecting…", tagged MANUAL when it was typed here). That
/// list scrolls inside the sheet (v45) with a fade at its foot; the
/// divider and "Enter IP Manually" are pinned below it, always visible,
/// and swap to the entry view inside the same sheet. Only the selected
/// row carries a tick; the others give the subtitle the full width (v47).
/// The list is live: it re-derives from the owner on every broadcast and
/// tick. Stateful so the draft survives a resize.
class AmpSheet extends ConsumerStatefulWidget {
  const AmpSheet({super.key});

  static final RegExp ipv4 = RegExp(
    r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$',
  );

  @override
  ConsumerState<AmpSheet> createState() => _AmpSheetState();

  /// The plain part of a row's second line (mockup `renderAmps()` `base`,
  /// v47: "model name above, IP only below, no friendly name"): the ip, or
  /// nothing when the ip is already the title — except an online row
  /// titled by its ip, which reads "Online" so the line is never empty.
  /// Joined to [statusFor] with " · " by the row.
  static String subtitleFor(AmpRef amp, {required bool selected}) {
    final base = amp.displayName == amp.ip ? '' : amp.ip;
    if (amp.online && base.isEmpty) return 'Online';
    return base;
  }

  /// The accent-coloured status of a silent row: the waiting word for the
  /// selection, "Last seen …" for the rest. `null` for an online row.
  static String? statusFor(AmpRef amp, {required bool selected}) {
    if (amp.online) return null;
    if (selected) return DeviceCard.waitingStatusFor(amp);
    return 'Last seen ${lastSeenLabel(amp.silentFor ?? Duration.zero)}';
  }

  /// The quantized silence (`AmpRef.silentFor`) as the mockup prints it.
  static String lastSeenLabel(Duration silentFor) {
    if (silentFor < const Duration(minutes: 1)) return 'just now';
    if (silentFor < const Duration(hours: 1)) return '${silentFor.inMinutes} min ago';
    return '${silentFor.inHours} h ago';
  }

}

class _AmpSheetState extends ConsumerState<AmpSheet> {
  bool _showManual = false;
  final TextEditingController _ip = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ip.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  bool get _ipValid => AmpSheet.ipv4.hasMatch(_ip.text.trim());

  void _connectManual() {
    if (!_ipValid) return;
    ref.read(ampStateProvider.notifier).addManualAmp(_ip.text.trim());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(controlViewStateProvider);
    popWhenSlotLeaves(ref, context, SheetKind.amp);
    return SheetScaffold(
      title: _showManual ? 'Enter IP Address' : 'Choose Amplifier',
      subtitle: _showManual ? 'Connect to an amplifier by its address' : 'Listening for amplifiers',
      // The entry view's way back is a bare chevron beside the title (the
      // owner's 2026-09-23 mockup update), not a "Back to list" line.
      onBack: _showManual ? () => setState(() => _showManual = false) : null,
      backKey: ControlKeys.sheetBack,
      // The listening arcs only exist (and so only animate) on the list view.
      subtitleLeading: _showManual ? null : const ListeningArcs(),
      bodyFade: _showManual ? null : listFade,
      footer: _showManual ? null : _buildManualRow(context),
      child: _showManual ? _buildManual(context) : _buildList(context, state),
    );
  }

  /// v45: `mask-image: linear-gradient(to bottom, #000 calc(100% - 14px), transparent)`.
  static const double listFade = 14;

  /// The pinned foot of the list view: divider + "Enter IP Manually".
  Widget _buildManualRow(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: t.divider, margin: const EdgeInsets.symmetric(vertical: 6)),
        AdaptivePressable(
          key: ControlKeys.ampManualRow,
          onTap: () => setState(() => _showManual = true),
          borderRadius: BorderRadius.circular(12),
          builder: (context, pressed) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
            decoration: BoxDecoration(
              color: pressed ? t.surface2 : null,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: _AmpRow.leadingBox,
                  height: 32,
                  child: Center(child: ManualEntryGlyph(size: 15)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Enter IP Manually', style: theme.type.body(size: 15, color: t.text))),
                const ChevronMark(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context, ControlViewState state) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final notifier = ref.read(ampStateProvider.notifier);
    // "None" is current only when nothing is selected — never while the
    // chosen amp is merely silent (the 3.0.8 caveat, closed in 3.9.0).
    final noneSelected = state.connection == ConnectionPhase.notConnected;
    final selectedIp = state.selectedAmp?.ip;
    final responding = [for (final a in state.knownAmps) if (a.online) a];
    final silent = [for (final a in state.knownAmps) if (!a.online) a];

    Widget divider() => Container(height: 1, color: t.divider, margin: const EdgeInsets.symmetric(vertical: 6));

    Widget row(AmpRef amp) {
      final selected = amp.ip == selectedIp;
      return _AmpRow(
        key: ControlKeys.ampRow(amp.ip),
        selected: selected,
        dimmed: !amp.online && !selected,
        leading: DeviceDot(
          state: amp.online
              ? DeviceDotState.connected
              : selected
              ? DeviceDotState.waiting
              : DeviceDotState.off,
        ),
        title: amp.displayName,
        titleStyle: theme.type.body(
          size: 15,
          weight: FontWeight.w600,
          color: selected ? t.copperBright : t.text,
        ),
        tag: amp.manual ? 'Manual' : null,
        subtitle: AmpSheet.subtitleFor(amp, selected: selected),
        status: AmpSheet.statusFor(amp, selected: selected),
        onTap: () {
          notifier.selectAmp(amp);
          Navigator.of(context).pop();
        },
      );
    }

    return Column(
      key: ControlKeys.ampList,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AmpRow(
          key: ControlKeys.ampNoneRow,
          selected: noneSelected,
          leading: Container(
            width: DeviceDot.defaultSize,
            height: DeviceDot.defaultSize,
            decoration: noneSelected
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: t.copperBright, width: 1.5),
                    boxShadow: [BoxShadow(color: t.accentTint(0.4), blurRadius: 6, spreadRadius: 1)],
                  )
                : null,
            child: noneSelected ? null : const DeviceDot(state: DeviceDotState.none),
          ),
          title: 'None',
          titleStyle: theme.type.body(
            size: 15,
            color: noneSelected ? t.copperBright : t.textDim,
            fontStyle: noneSelected ? FontStyle.normal : FontStyle.italic,
          ),
          subtitle: "Don't connect to any amplifier",
          onTap: () {
            notifier.selectAmp(null);
            Navigator.of(context).pop();
          },
        ),
        divider(),
        for (final amp in responding) row(amp),
        if (silent.isNotEmpty) ...[
          const _AmpGroupLabel('Not responding'),
          for (final amp in silent) row(amp),
        ],
      ],
    );
  }

  Widget _buildManual(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdaptiveTextField(
          controller: _ip,
          placeholder: '192.168.0.1',
          autofocus: true,
          onSubmitted: (_) => _connectManual(),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 2),
          child: Text(
            "Find this in your router's device list or the Devialet app.",
            style: theme.type.mono(size: 11.5, color: t.textFaint),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: AdaptivePressable(
            onTap: _connectManual,
            enabled: _ipValid,
            borderRadius: BorderRadius.circular(16),
            builder: (context, pressed) => Opacity(
              opacity: _ipValid ? 1 : 0.4,
              child: Container(
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [t.copperBright, t.copper],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  'Connect',
                  style: theme.type.display(size: 14.5, color: const Color(0xFF1A120B)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The mockup's `.amp-group`: a quiet uppercase label over the silent
/// rows (10.5 px display face, 0.16 em, faint; margins 14 / 10 / 2).
class _AmpGroupLabel extends StatelessWidget {
  const _AmpGroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 14, left: 10, right: 10, bottom: 2),
      child: Text(
        text.toUpperCase(),
        key: ControlKeys.ampGroupLabel,
        style: theme.type.display(size: 10.5, weight: FontWeight.w600, letterSpacingEm: 0.16, color: theme.tokens.textFaint),
      ),
    );
  }
}

class _AmpRow extends StatelessWidget {
  /// The leading slot, shared by every row (dot, None ring, keyboard) so
  /// the titles line up: wide enough for the keyboard glyph's optically
  /// scaled box (15 · 1.05 · 1.25 ≈ 19.7).
  static const double leadingBox = 20;

  const _AmpRow({
    super.key,
    required this.selected,
    required this.leading,
    required this.title,
    required this.titleStyle,
    required this.subtitle,
    required this.onTap,
    this.status,
    this.tag,
    this.dimmed = false,
  });

  final bool selected;
  final Widget leading;
  final String title;
  final TextStyle titleStyle;

  /// The plain second line; [status], when present, follows it in the
  /// accent colour, joined by " · " (nothing joins an empty [subtitle]).
  final String subtitle;
  final String? status;

  /// A small bordered chip after the title (mockup `.amp-tag`: "Manual").
  final String? tag;

  /// A silent, unselected amp: dot and text at half opacity (mockup
  /// `.amp-option.offline:not(.connected)`); still tappable.
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final subtitleStyle = theme.type.mono(size: 12, color: t.textDim);
    final status = this.status;
    final tag = this.tag;
    return AdaptivePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      builder: (context, pressed) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
          color: pressed ? t.surface2 : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Opacity(
                opacity: dimmed ? 0.5 : 1,
                child: Row(
                  children: [
                    SizedBox.square(dimension: _AmpRow.leadingBox, child: Center(child: leading)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                              ),
                              if (tag != null) _Tag(tag, selected: selected),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: subtitle),
                                  if (status != null) ...[
                                    if (subtitle.isNotEmpty) const TextSpan(text: ' · '),
                                    TextSpan(text: status, style: subtitleStyle.copyWith(color: t.copperBright)),
                                  ],
                                ],
                              ),
                              style: subtitleStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // v47: no reserved tick space on unselected rows — the
            // subtitle gets the full width.
            if (selected) const CheckMark(),
          ],
        ),
      ),
    );
  }
}

/// Mockup `.amp-tag`: 9.5 px mono, uppercase, 1 px `divider` border,
/// radius 6, 1 × 6 padding, 8 before it; accent-coloured on the selected row.
class _Tag extends StatelessWidget {
  const _Tag(this.text, {required this.selected});

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: selected ? t.copperDim : t.divider),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text.toUpperCase(),
        style: theme.type.mono(
          size: 9.5,
          weight: FontWeight.w600,
          letterSpacingEm: 0.06,
          color: selected ? t.copperBright : t.textDim,
        ),
      ),
    );
  }
}
