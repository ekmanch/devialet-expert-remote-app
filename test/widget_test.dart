import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/app.dart';

void main() {
  testWidgets('debug screen renders without a real device connected', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: DevialetRemoteApp()));
    await tester.pump();

    expect(find.textContaining('MANUAL TEST SCREEN'), findsOneWidget);
    expect(find.text('Power ON'), findsOneWidget);
  });
}
