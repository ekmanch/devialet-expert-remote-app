import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/orientation_policy.dart';
import 'domain/amp_trace.dart';
import 'domain/debug/simulated_amp.dart';
import 'domain/model_name_resolver.dart';
import 'domain/monotonic_clock.dart';
import 'domain/settings/hydrated_settings.dart';
import 'domain/settings/settings_store.dart';
import 'networking/model_name_source.dart';
import 'networking/multicast_dns_model_name_source.dart';
import 'platform/android_multicast_lock.dart';
import 'platform/bonjour_model_name_source.dart';
import 'ui/app.dart';

/// Bundled fonts (pubspec.yaml `fonts:`) are OFL-licensed; the licence
/// text ships as assets and is surfaced through the framework's licence
/// registry (Settings → About → licences, Task 3.4.x).
const List<(String, String)> _fontLicences = [
  ('Space Grotesk', 'assets/fonts/space_grotesk/OFL.txt'),
  ('JetBrains Mono', 'assets/fonts/jetbrains_mono/OFL.txt'),
  ('Inter', 'assets/fonts/inter/OFL.txt'),
];

/// Task 3.9.5: the platform's `_spotify-connect._tcp` browser. Pure-Dart
/// `multicast_dns` on Android (behind the multicast lock) and on desktop;
/// Bonjour on iOS, where pure-Dart multicast would need Apple's multicast
/// entitlement. The real OS, not the UI variant: this is a socket, not a
/// look.
ModelNameSource platformModelNameSource() {
  if (Platform.isAndroid) return MulticastDnsModelNameSource(lock: const AndroidMulticastLock());
  if (Platform.isIOS) return const BonjourModelNameSource();
  return MulticastDnsModelNameSource(lock: const NoopMulticastLock());
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  OrientationPolicy.apply();
  LicenseRegistry.addLicense(() async* {
    for (final (name, asset) in _fontLicences) {
      yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString(asset));
    }
  });
  // Settings are loaded and self-healed before anything binds (Task
  // 3.3.2); the native launch screen covers the one platform call.
  final hydrated = await hydrateSettings(SharedPreferencesSettingsStore.open, log: debugPrint);
  runApp(
    ProviderScope(
      overrides: [
        hydratedSettingsProvider.overrideWithValue(hydrated),
        modelNameSourceProvider.overrideWithValue(platformModelNameSource()),
        // Debug builds route commands for TEST-NET IPs to the simulated amp
        // and narrate the owner to logcat (`[amp]` lines, Task 3.5.2).
        if (kDebugMode) debugCommandSinkOverride,
        if (kDebugMode) ampTraceProvider.overrideWith((ref) => AmpTrace(debugPrint, ref.watch(monotonicClockProvider))),
      ],
      child: const DevialetRemoteApp(),
    ),
  );
}
