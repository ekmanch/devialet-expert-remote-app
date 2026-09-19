import 'package:flutter/widgets.dart';

/// A label whose intrinsic width is that of its *widest possible* text,
/// so "Mute"/"Unmute" and "Power On"/"Powering on…" never shift the icon
/// next to them when they toggle (TODO 2.0.7, checklist item 16). Every
/// non-current candidate is laid out invisibly under the live text.
class WidestLabel extends StatelessWidget {
  const WidestLabel({
    super.key,
    required this.candidates,
    required this.current,
    required this.style,
    this.alignment = Alignment.center,
    this.textKey,
  });

  final List<String> candidates;
  final String current;
  final TextStyle style;
  final AlignmentGeometry alignment;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: alignment,
      children: [
        for (final candidate in candidates)
          if (candidate != current)
            Visibility(
              visible: false,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Text(candidate, style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
            ),
        Text(current, key: textKey, style: style, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
