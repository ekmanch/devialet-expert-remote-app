import 'package:flutter/widgets.dart';

import '../../domain/control_view_state.dart';
import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../widgets/dimmed_group.dart';
import '../widgets/ring_spinner.dart';
import '../widgets/stroke_icons.dart';
import '../widgets/widest_label.dart';
import 'control_keys.dart';

class ActionButtonColors {
  const ActionButtonColors({required this.background, required this.border, required this.foreground});

  final Color background;
  final Color border;
  final Color foreground;
}

/// Mute | Power. Labels are sized to their widest candidate so toggling
/// never moves the icon (TODO 2.0.7); the icon slot is a fixed 16×16.
class ActionRow extends StatelessWidget {
  const ActionRow({
    super.key,
    required this.state,
    required this.onMute,
    required this.onPower,
  });

  final ControlViewState state;
  final VoidCallback onMute;
  final VoidCallback onPower;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Row(
        children: [
          Expanded(
            child: DimmedGroup(
              key: ControlKeys.muteButton,
              dimmed: state.hasAmp && !state.volumeGroupEnabled,
              child: MuteButton(isMuted: state.isMuted, enabled: state.volumeGroupEnabled, onTap: onMute),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PowerButton(
              key: ControlKeys.powerButton,
              power: state.power,
              hasAmp: state.hasAmp,
              enabled: state.powerEnabled,
              onTap: onPower,
            ),
          ),
        ],
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.labels,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.colorsFor,
    this.labelKey,
    this.iconKey,
  });

  static const List<String> _noLabels = [];

  /// Every label this button can show; width = the widest.
  final List<String> labels;
  final String label;
  final Widget icon;
  final bool enabled;
  final VoidCallback onTap;
  final ActionButtonColors Function(bool pressed) colorsFor;
  final Key? labelKey;
  final Key? iconKey;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return AdaptivePressable(
      onTap: onTap,
      enabled: enabled,
      borderRadius: BorderRadius.circular(16),
      builder: (context, pressed) {
        final c = colorsFor(pressed);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          decoration: BoxDecoration(
            color: c.background,
            border: Border.all(color: c.border),
            borderRadius: BorderRadius.circular(16),
            boxShadow: t.cardShadow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox.square(key: iconKey, dimension: 16, child: icon),
              const SizedBox(width: 8),
              Flexible(
                child: WidestLabel(
                  candidates: labels.isEmpty ? _noLabels : labels,
                  current: label,
                  textKey: labelKey,
                  style: theme.type.body(size: 13.5, weight: FontWeight.w600, letterSpacingEm: 0.02, color: c.foreground),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MuteButton extends StatelessWidget {
  const MuteButton({super.key, required this.isMuted, required this.enabled, required this.onTap});

  static const List<String> labels = ['Mute', 'Unmute'];

  final bool isMuted;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    final fg = isMuted ? t.copperBright : t.text;
    return ActionButton(
      labels: labels,
      label: isMuted ? 'Unmute' : 'Mute',
      labelKey: ControlKeys.muteLabel,
      iconKey: ControlKeys.muteIcon,
      icon: StrokeIcon(isMuted ? StrokeIconKind.speakerMuted : StrokeIconKind.speaker, color: fg),
      enabled: enabled,
      onTap: onTap,
      colorsFor: (pressed) => isMuted
          ? ActionButtonColors(background: t.accentTint(0.14), border: t.copperDim, foreground: t.copperBright)
          : ActionButtonColors(background: t.surface, border: t.divider, foreground: t.text),
    );
  }
}

class PowerButton extends StatelessWidget {
  const PowerButton({
    super.key,
    required this.power,
    required this.hasAmp,
    required this.enabled,
    required this.onTap,
  });

  static const List<String> labels = ['Power Off', 'Power On', 'Powering on…'];

  final PowerPhase power;
  final bool hasAmp;
  final bool enabled;
  final VoidCallback onTap;

  static String labelFor(PowerPhase power, {required bool hasAmp}) {
    if (!hasAmp) return 'Power Off';
    return switch (power) {
      PowerPhase.on => 'Power Off',
      PowerPhase.off => 'Power On',
      PowerPhase.booting => 'Powering on…',
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    final booting = hasAmp && power == PowerPhase.booting;
    final off = hasAmp && power == PowerPhase.off;

    ActionButtonColors colorsFor(bool pressed) {
      if (booting) {
        return ActionButtonColors(background: t.surface, border: t.warning, foreground: t.warningBright);
      }
      if (off) {
        return pressed
            ? ActionButtonColors(background: t.surface, border: t.success, foreground: t.successBright)
            : ActionButtonColors(background: t.surface, border: t.divider, foreground: t.textDim);
      }
      return pressed
          ? ActionButtonColors(background: t.surface, border: t.danger, foreground: t.danger)
          : ActionButtonColors(background: t.surface, border: t.divider, foreground: t.text);
    }

    return ActionButton(
      labels: labels,
      label: labelFor(power, hasAmp: hasAmp),
      labelKey: ControlKeys.powerLabel,
      iconKey: ControlKeys.powerIcon,
      icon: booting
          ? RingSpinner(color: t.warningBright, trackColor: const Color(0x40E0B563))
          : StrokeIcon(StrokeIconKind.power, color: colorsFor(false).foreground),
      enabled: enabled,
      onTap: onTap,
      colorsFor: colorsFor,
    );
  }
}
