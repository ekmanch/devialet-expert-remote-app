import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/control_view_state.dart';
import '../../domain/amp_state_owner.dart';
import '../platform/adaptive_pressable.dart';
import '../platform/adaptive_text_field.dart';
import '../theme/app_theme.dart';
import '../widgets/arcs.dart';
import '../widgets/check_mark.dart';
import '../widgets/sheet_scaffold.dart';
import 'device_card.dart';
import 'manual_entry_glyph.dart';

/// "Choose Amplifier" (TODO 2.0.3): "None" first (italic, dashed dot,
/// "Don't connect to any amplifier"), divider, discovered amps
/// (`model ?? name`, "· name unresolved" when only the UDP name is
/// known), then "Enter IP Manually", which swaps to the entry view
/// inside the same sheet. Stateful so the draft survives a resize.
class AmpSheet extends ConsumerStatefulWidget {
  const AmpSheet({super.key});

  static final RegExp ipv4 = RegExp(
    r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$',
  );

  @override
  ConsumerState<AmpSheet> createState() => _AmpSheetState();
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
    return SheetScaffold(
      title: _showManual ? 'Enter IP Address' : 'Choose Amplifier',
      subtitle: _showManual ? 'Connect to an amplifier by its address' : 'Amplifiers found on your network',
      // The listening arcs only exist (and so only animate) on the list view.
      subtitleLeading: _showManual ? null : const ListeningArcs(),
      child: _showManual ? _buildManual(context) : _buildList(context, state),
    );
  }

  Widget _buildList(BuildContext context, ControlViewState state) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final notifier = ref.read(ampStateProvider.notifier);
    final noneSelected = state.selectedAmp == null;

    Widget divider() => Container(height: 1, color: t.divider, margin: const EdgeInsets.symmetric(vertical: 6));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AmpRow(
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
        for (final amp in state.knownAmps)
          _AmpRow(
            selected: amp == state.selectedAmp,
            leading: const DeviceDot(state: DeviceDotState.connected),
            title: amp.displayName,
            titleStyle: theme.type.body(
              size: 15,
              weight: FontWeight.w600,
              color: amp == state.selectedAmp ? t.copperBright : t.text,
            ),
            subtitle: amp.isResolved ? '${amp.name} · ${amp.ip}' : '${amp.ip} · name unresolved',
            onTap: () {
              notifier.selectAmp(amp);
              Navigator.of(context).pop();
            },
          ),
        if (state.knownAmps.isNotEmpty) divider(),
        AdaptivePressable(
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

  Widget _buildManual(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showManual = false),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('‹ Back to list', style: theme.type.mono(size: 12, color: t.copperBright)),
          ),
        ),
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

class _AmpRow extends StatelessWidget {
  /// The leading slot, shared by every row (dot, None ring, keyboard) so
  /// the titles line up: wide enough for the keyboard glyph's optically
  /// scaled box (15 · 1.05 · 1.15 ≈ 18.1).
  static const double leadingBox = 20;

  const _AmpRow({
    required this.selected,
    required this.leading,
    required this.title,
    required this.titleStyle,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final Widget leading;
  final String title;
  final TextStyle titleStyle;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
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
            SizedBox.square(dimension: _AmpRow.leadingBox, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.type.mono(size: 12, color: t.textDim),
                    ),
                  ),
                ],
              ),
            ),
            Opacity(
              opacity: selected ? 1 : 0,
              child: const CheckMark(),
            ),
          ],
        ),
      ),
    );
  }
}
