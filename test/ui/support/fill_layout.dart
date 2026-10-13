import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/control/control_fill_layout.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/control_layout.dart';

/// The `fitDial()` rule re-derived from what is on screen, so a test
/// asserts the dial's size against measured parts rather than a number
/// copied from the code (checklist 14/20): `top` from where the dial
/// starts, the round row's own height, `bottom` from where the Source
/// label starts.
class FillMeasurement {
  FillMeasurement(WidgetTester tester)
    : column = tester.getRect(find.byKey(ControlKeys.column)),
      dial = tester.getRect(find.byKey(ControlKeys.dial)),
      roundRow = tester.getRect(find.byKey(ControlKeys.roundRow)),
      sourceLabel = tester.getRect(find.byKey(ControlKeys.sourceLabel)),
      sourceTrigger = tester.getRect(find.byKey(ControlKeys.sourceTrigger));

  final Rect column;
  final Rect dial;
  final Rect roundRow;
  final Rect sourceLabel;
  final Rect sourceTrigger;

  double get top => dial.top - column.top - kControlDialTop;
  double get bottom => column.bottom - sourceLabel.top;
  double get natural => FilledControlLayout.naturalHeight(top: top, roundRow: roundRow.height, bottom: bottom);
  double get spare => column.height - natural + kControlFillMinGap;
  double get expectedDial => FilledControlLayout.dialSizeFor(width: column.width, spare: spare);
  double get k => dial.width / kControlDialBase;

  /// The gap the spacer ended up with (round row → Source label).
  double get gap => sourceLabel.top - roundRow.bottom;
}
