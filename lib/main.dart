import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/orientation_policy.dart';
import 'domain/debug/simulated_amp.dart';
import 'ui/app.dart';

/// Bundled fonts (pubspec.yaml `fonts:`) are OFL-licensed; the licence
/// text ships as assets and is surfaced through the framework's licence
/// registry (Settings → About → licences, Task 3.4.x).
const List<(String, String)> _fontLicences = [
  ('Space Grotesk', 'assets/fonts/space_grotesk/OFL.txt'),
  ('JetBrains Mono', 'assets/fonts/jetbrains_mono/OFL.txt'),
  ('Inter', 'assets/fonts/inter/OFL.txt'),
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  OrientationPolicy.apply();
  LicenseRegistry.addLicense(() async* {
    for (final (name, asset) in _fontLicences) {
      yield LicenseEntryWithLineBreaks([name], await rootBundle.loadString(asset));
    }
  });
  runApp(
    ProviderScope(
      // Debug builds route commands for TEST-NET IPs to the simulated amp.
      overrides: [if (kDebugMode) debugCommandSinkOverride],
      child: const DevialetRemoteApp(),
    ),
  );
}
