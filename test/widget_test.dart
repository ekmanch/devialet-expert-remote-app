import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/control/control_screen.dart';

import 'ui/support/pump_control.dart';

void main() {
  testWidgets('home is the Control screen; no debug bar under the column (removed 2026-09-23)', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(hermeticApp());
    await tester.pump();

    expect(find.byType(ControlScreen), findsOneWidget);
    expect(find.text('Expert Pro Remote'), findsOneWidget);
    expect(find.textContaining('SIM \u00b7'), findsNothing);
    expect(find.text('Net'), findsNothing);
  });
}
