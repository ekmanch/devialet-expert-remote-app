import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/window_class.dart';

void main() {
  group('WindowClass.fromSize (Material 3 breakpoints)', () {
    test('width boundaries 599 / 600 / 839 / 840', () {
      expect(WindowClass.widthClassFor(599), WindowWidthClass.compact);
      expect(WindowClass.widthClassFor(600), WindowWidthClass.medium);
      expect(WindowClass.widthClassFor(839), WindowWidthClass.medium);
      expect(WindowClass.widthClassFor(840), WindowWidthClass.expanded);
    });

    test('height boundaries 479 / 480 / 899 / 900', () {
      expect(WindowClass.heightClassFor(479), WindowHeightClass.compact);
      expect(WindowClass.heightClassFor(480), WindowHeightClass.medium);
      expect(WindowClass.heightClassFor(899), WindowHeightClass.medium);
      expect(WindowClass.heightClassFor(900), WindowHeightClass.expanded);
    });

    test('phone portrait / landscape / tablet', () {
      expect(WindowClass.fromSize(const Size(390, 844)), const WindowClass(width: WindowWidthClass.compact, height: WindowHeightClass.medium));
      expect(WindowClass.fromSize(const Size(844, 390)), const WindowClass(width: WindowWidthClass.expanded, height: WindowHeightClass.compact));
      expect(WindowClass.fromSize(const Size(1024, 768)), const WindowClass(width: WindowWidthClass.expanded, height: WindowHeightClass.medium));
    });
  });

  test('WindowClassScope notifies only when the class changes', () {
    WindowClassScope scope(Size size) => WindowClassScope(value: WindowClass.fromSize(size), child: const SizedBox());
    expect(scope(const Size(391, 844)).updateShouldNotify(scope(const Size(390, 844))), isFalse);
    expect(scope(const Size(1024, 768)).updateShouldNotify(scope(const Size(390, 844))), isTrue);
  });
}
