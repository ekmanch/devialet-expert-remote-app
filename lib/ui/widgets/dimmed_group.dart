import 'package:flutter/widgets.dart';

/// The mockup's `.disabled-overlay` (opacity 0.4, no pointer events) and
/// `.dim` (opacity 0.5, still tappable) in one place, so every gate point
/// dims the same way (TODO 2.0.8). Content underneath keeps its last-known
/// text; nothing is blanked.
///
/// [absorb] chooses what a blocked tap does: by default it passes through
/// to whatever lies under the group (`IgnorePointer`); with [absorb] the
/// group swallows it (`AbsorbPointer`) — the device card's dimmed power
/// circle, which must not open the amp sheet behind it (owner decision
/// 2026-09-26: "no taps", unlike the mockup's `pointer-events:none`).
class DimmedGroup extends StatelessWidget {
  const DimmedGroup({
    super.key,
    required this.dimmed,
    required this.child,
    this.opacity = 0.4,
    this.blockTaps = true,
    this.absorb = false,
  });

  final bool dimmed;
  final double opacity;
  final bool blockTaps;
  final bool absorb;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final blocked = dimmed && blockTaps;
    final content = ExcludeSemantics(excluding: blocked, child: child);
    return Opacity(
      opacity: dimmed ? opacity : 1.0,
      child: absorb
          ? AbsorbPointer(absorbing: blocked, child: content)
          : IgnorePointer(ignoring: blocked, child: content),
    );
  }
}
