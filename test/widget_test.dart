import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/control/control_screen.dart';

import 'ui/support/pump_control.dart';

void main() {
  testWidgets('home is the Control screen and the debug bar reaches the network test screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(hermeticApp());
    await tester.pump();

    expect(find.byType(ControlScreen), findsOneWidget);
    expect(find.text('Expert Pro Remote'), findsOneWidget);

    await tester.ensureVisible(find.byKey(ControlKeys.debugNet));
    await tester.tap(find.byKey(ControlKeys.debugNet));
    await tester.pumpAndSettle();

    expect(find.textContaining('MANUAL TEST SCREEN'), findsOneWidget);
  });
}
