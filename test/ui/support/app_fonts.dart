import 'package:flutter/services.dart';

/// Loads the bundled fonts into the test binding so text metrics match
/// the device instead of the test framework's placeholder font (whose
/// glyphs are square: a 26 px title measures ~26 px tall on it, but real
/// faces have their own ascent/descent). Needed by any guard that asserts
/// a *fit* — the Control column on the Galaxy S25, for one. Idempotent.
Future<void> loadAppFonts() async {
  if (_loaded) return;
  _loaded = true;
  const files = {
    'SpaceGrotesk': [
      'assets/fonts/space_grotesk/space_grotesk_regular.ttf',
      'assets/fonts/space_grotesk/space_grotesk_medium.ttf',
      'assets/fonts/space_grotesk/space_grotesk_semibold.ttf',
      'assets/fonts/space_grotesk/space_grotesk_bold.ttf',
    ],
    'JetBrainsMono': [
      'assets/fonts/jetbrains_mono/jetbrains_mono_regular.ttf',
      'assets/fonts/jetbrains_mono/jetbrains_mono_medium.ttf',
      'assets/fonts/jetbrains_mono/jetbrains_mono_semibold.ttf',
    ],
    'Inter': [
      'assets/fonts/inter/Inter_18pt-Regular.ttf',
      'assets/fonts/inter/Inter_18pt-Medium.ttf',
      'assets/fonts/inter/Inter_18pt-SemiBold.ttf',
    ],
  };
  for (final entry in files.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(rootBundle.load(path));
    }
    await loader.load();
  }
}

bool _loaded = false;
