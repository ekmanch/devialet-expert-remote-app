import 'package:flutter/widgets.dart';

/// The mockup's `.disabled-overlay` (opacity 0.4, no pointer events) and
/// `.dim` (opacity 0.5, still tappable) in one place, so every gate point
/// dims the same way (TODO 2.0.8). Content underneath keeps its last-known
/// text; nothing is blanked.
class DimmedGroup extends StatelessWidget {
  const DimmedGroup({
    super.key,
    required this.dimmed,
    required this.child,
    this.opacity = 0.4,
    this.blockTaps = true,
  });

  final bool dimmed;
  final double opacity;
  final bool blockTaps;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final blocked = dimmed && blockTaps;
    return Opacity(
      opacity: dimmed ? opacity : 1.0,
      child: IgnorePointer(
        ignoring: blocked,
        child: ExcludeSemantics(excluding: blocked, child: child),
      ),
    );
  }
}
