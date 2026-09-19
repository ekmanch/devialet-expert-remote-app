import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/orientation_policy.dart';

void main() {
  testWidgets('phone display (shortest side < 600 dp) locks to portrait', (tester) async {
    tester.view.display.size = const Size(1080, 2340);
    tester.view.display.devicePixelRatio = 3.0; // 360 × 780 dp
    addTearDown(tester.view.display.reset);
    expect(OrientationPolicy.isPhoneDisplay(tester.view), isTrue);
    expect(OrientationPolicy.orientationsFor(tester.view), [DeviceOrientation.portraitUp]);
  });

  testWidgets('tablet display (shortest side ≥ 600 dp) keeps every orientation', (tester) async {
    tester.view.display.size = const Size(2000, 1200);
    tester.view.display.devicePixelRatio = 2.0; // 1000 × 600 dp
    addTearDown(tester.view.display.reset);
    expect(OrientationPolicy.isPhoneDisplay(tester.view), isFalse);
    expect(OrientationPolicy.orientationsFor(tester.view), DeviceOrientation.values);
  });

  testWidgets('the decision follows the display, not the window (split screen)', (tester) async {
    tester.view.display.size = const Size(2000, 1200);
    tester.view.display.devicePixelRatio = 2.0;
    tester.view.physicalSize = const Size(700, 1200); // phone-width window on a tablet
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.view.display.reset);
    expect(OrientationPolicy.isPhoneDisplay(tester.view), isFalse);
  });

  test('unknown display defaults to the phone policy', () {
    expect(OrientationPolicy.isPhoneDisplay(null), isTrue);
    expect(OrientationPolicy.orientationsFor(null), [DeviceOrientation.portraitUp]);
  });
}
