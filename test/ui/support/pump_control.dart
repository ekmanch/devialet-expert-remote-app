import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state_provider.dart';
import 'package:devialet_expert_remote_app/ui/app.dart';
import 'package:devialet_expert_remote_app/ui/control/control_screen.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_pressable.dart';

/// Galaxy S25-ish logical size; the mockups are 390 wide.
const Size phonePortrait = Size(390, 844);
const Size phoneLandscape = Size(844, 390);
const Size tabletLandscape = Size(1024, 768);

/// Pumps the real app root with the fake state and variant overridden —
/// the first use of the ProviderScope-override pattern in the widget
/// tests (CLAUDE.md, "Testing"). Never touches real networking: the
/// Control screen doesn't watch the transport providers.
Future<void> pumpControl(
  WidgetTester tester, {
  required ControlViewState state,
  UiVariant variant = UiVariant.android,
  Size size = phonePortrait,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        uiVariantProvider.overrideWithValue(variant),
        controlViewStateProvider.overrideWith(() => ControlViewNotifier(initial: state)),
      ],
      child: const DevialetRemoteApp(),
    ),
  );
  await tester.pump();
}

Future<void> resizeWindow(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ControlScreen)));

ControlViewState readState(WidgetTester tester) => containerOf(tester).read(controlViewStateProvider);

/// The opacity applied by the `DimmedGroup` carrying [key].
double opacityAt(WidgetTester tester, Key key) {
  final finder = find.descendant(of: find.byKey(key), matching: find.byType(Opacity)).first;
  return tester.widget<Opacity>(finder).opacity;
}

String textAt(WidgetTester tester, Key key) => tester.widget<Text>(find.byKey(key)).data!;

bool visibilityOf(WidgetTester tester, Key key) {
  final finder = find.ancestor(of: find.byKey(key), matching: find.byType(Visibility)).first;
  return tester.widget<Visibility>(finder).visible;
}

/// Taps the pressable row that contains [text]. Rows paint their ripple
/// in an overlay above the content, so the content itself is never the
/// hit-test target; aiming at the `AdaptivePressable` is the honest tap.
Future<void> tapRow(WidgetTester tester, String text) async {
  final row = find.ancestor(of: find.text(text), matching: find.byType(AdaptivePressable)).first;
  await tester.tap(row);
}
