import 'dart:ui' show FlutterView;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Owner decision 2026-09-19: the app does not rotate on a **phone** — it
/// stays portrait. Tablets keep every orientation, because the two-pane
/// expanded layout (Task 3.11.x) is a landscape layout and Google Play's
/// large-screen guidelines penalise portrait-locked tablet apps.
///
/// "Phone" is decided by the *display*, not the current window (a tablet
/// in split screen presents a phone-width window but must not get locked),
/// using the standard 600 dp shortest-side threshold. If the display is
/// unknown, lock: phones are the primary target and a phone that rotates is
/// the outcome the owner asked not to have.
abstract final class OrientationPolicy {
  static const double tabletMinShortestSideDp = 600;

  static const List<DeviceOrientation> phone = [DeviceOrientation.portraitUp];
  static const List<DeviceOrientation> tablet = DeviceOrientation.values;

  static bool isPhoneDisplay(FlutterView? view) {
    final display = view?.display;
    if (display == null) return true;
    final dp = display.size / display.devicePixelRatio;
    return dp.shortestSide < tabletMinShortestSideDp;
  }

  static List<DeviceOrientation> orientationsFor(FlutterView? view) =>
      isPhoneDisplay(view) ? phone : tablet;

  /// Call once after `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<void> apply() =>
      SystemChrome.setPreferredOrientations(orientationsFor(WidgetsBinding.instance.platformDispatcher.implicitView));
}
