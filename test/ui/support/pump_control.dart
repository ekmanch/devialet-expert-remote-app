import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/debug/simulated_amp.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/domain/devialet_client_provider.dart';
import 'package:devialet_expert_remote_app/domain/monotonic_clock.dart';
import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/hydrated_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_store.dart';
import 'package:devialet_expert_remote_app/ui/app.dart';
import 'package:devialet_expert_remote_app/ui/platform/platform_style.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_theme.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_tokens.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_typography.dart';
import 'package:devialet_expert_remote_app/ui/control/control_screen.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_pressable.dart';
import 'package:devialet_expert_remote_app/ui/settings/url_opener.dart';

import '../../domain/support/fake_time.dart';
import '../../domain/support/settings_support.dart';
import '../../networking/fake_udp_transport.dart';

/// Galaxy S25-ish logical size; the mockups are 390 wide.
const Size phonePortrait = Size(390, 844);
const Size phoneLandscape = Size(844, 390);
const Size tabletLandscape = Size(1024, 768);

/// The app root with overrides that keep the real owner off the network
/// and off the wall clock: a fake transport (no socket), a frozen clock
/// (pending values never expire unless a test advances it) and no stale
/// tick. [variant] is left to the real resolver when null.
Widget hermeticApp({
  UiVariant? variant,
  FakeClock? clock,
  Stream<void>? ticks,
  InMemorySettingsStore? settingsStore,
  AppSettings? initialSettings,
  Object? storeError,
  UrlOpener? urlOpener,
}) {
  return ProviderScope(
    overrides: [
      if (variant != null) uiVariantProvider.overrideWithValue(variant),
      devialetTransportProvider.overrideWithValue(FakeUdpTransport()),
      monotonicClockProvider.overrideWithValue(clock ?? FakeClock()),
      staleTickProvider.overrideWithValue(ticks ?? const Stream<void>.empty()),
      hydratedSettingsProvider.overrideWithValue(
        testHydrated(store: settingsStore, initial: initialSettings, storeError: storeError),
      ),
      if (urlOpener != null) urlOpenerProvider.overrideWithValue(urlOpener),
      // The hermetic app is the debug app: TEST-NET commands go to the
      // (inactive) simulated amp, real IPs would go to the fake socket.
      debugCommandSinkOverride,
    ],
    child: const DevialetRemoteApp(),
  );
}

/// A single widget under the same `AppTheme` the app installs, with no
/// screen, owner or `DimmedGroup` around it — for testing a control's own
/// behaviour in isolation (mirrors `DevialetRemoteApp.wrap`).
Widget themed(Widget child, {UiVariant variant = UiVariant.android, Brightness brightness = Brightness.dark}) {
  return MediaQuery(
    data: const MediaQueryData(size: phonePortrait),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: AppTheme(
        tokens: AppTokens.forBrightness(brightness),
        type: AppTypography.forVariant(variant),
        style: PlatformStyle.forVariant(variant),
        child: Center(
          child: SizedBox(width: phonePortrait.width, child: child),
        ),
      ),
    ),
  );
}

/// Pumps the real app root on the real owner, seeded with [state] through
/// the owner's ingest path (synthetic broadcasts from TEST-NET IPs), with
/// the variant overridden. Never touches real networking (checklist 19).
Future<void> pumpControl(
  WidgetTester tester, {
  required ControlViewState state,
  UiVariant variant = UiVariant.android,
  Size size = phonePortrait,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(hermeticApp(variant: variant));
  await tester.pump();
  seedFromControlView(containerOf(tester).read(ampStateProvider.notifier), state);
  await tester.pump();
}

Future<void> resizeWindow(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pump();
}

/// The Control screen stays mounted (offstage) under a pushed route.
ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ControlScreen, skipOffstage: false)));

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
Future<void> tapRow(WidgetTester tester, String text, {bool warnIfMissed = true}) async {
  final row = find.ancestor(of: find.text(text), matching: find.byType(AdaptivePressable)).first;
  await tester.tap(row, warnIfMissed: warnIfMissed);
}
