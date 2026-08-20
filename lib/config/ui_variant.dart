import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which platform's UI conventions to render (Material vs. iOS-native),
/// independent of the actual OS the app is running on.
enum UiVariant { android, ios }

/// Debug-only override, read once at process start. Pass
/// `--dart-define=UI_VARIANT=android` or `--dart-define=UI_VARIANT=ios` in
/// the run configuration to force a variant while running on either OS —
/// see README.md for the Android Studio run-configuration steps.
///
/// Deliberately gated behind [kDebugMode]: even if this define somehow
/// leaked into a release build, it's ignored and the real OS is used.
const String _uiVariantDefine = String.fromEnvironment('UI_VARIANT');

UiVariant resolveUiVariant() {
  if (kDebugMode) {
    switch (_uiVariantDefine) {
      case 'android':
        return UiVariant.android;
      case 'ios':
        return UiVariant.ios;
    }
  }
  return defaultTargetPlatform == TargetPlatform.iOS ? UiVariant.ios : UiVariant.android;
}

/// Route platform-specific styling decisions through this provider rather
/// than `Platform.isIOS` / `Theme.of(context).platform` directly, so they
/// stay overridable via the debug mechanism above (per CLAUDE.md, "Runtime
/// UI variant switching").
final uiVariantProvider = Provider<UiVariant>((ref) => resolveUiVariant());
