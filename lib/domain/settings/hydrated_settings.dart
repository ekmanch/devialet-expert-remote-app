import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';
import 'settings_store.dart';

/// The settings as loaded and healed **before anything binds** (Task
/// 3.3.2), plus the store to write back to. Produced by [hydrateSettings]
/// in `main()` and handed in through [hydratedSettingsProvider].
class HydratedSettings {
  const HydratedSettings({
    required this.store,
    required this.initial,
    this.repairs = const [],
    this.storeError,
  });

  final SettingsStore store;
  final AppSettings initial;
  final List<SettingRepair> repairs;

  /// Non-null when the real store could not be opened: the app runs on
  /// an in-memory store with defaults and **nothing persists** — a broken
  /// store must look broken (checklist 26), so the debug bar shows it and
  /// Task 3.4.x surfaces it in Settings.
  final Object? storeError;

  bool get storeUnavailable => storeError != null;
}

/// Required injection (checklist 2): `main()` and the test harness must
/// override this; an un-overridden read fails loudly at construction.
final hydratedSettingsProvider = Provider<HydratedSettings>(
  (_) => throw StateError('hydratedSettingsProvider must be overridden in main() / the test harness'),
);

/// Open → load → heal → write repairs back. Any failure opening or
/// reading falls back to an in-memory store with defaults; a failed
/// write-back is logged, not fatal.
Future<HydratedSettings> hydrateSettings(
  Future<SettingsStore> Function() open, {
  void Function(String message)? log,
}) async {
  final SettingsStore store;
  final Map<String, Object?> raw;
  try {
    store = await open();
    raw = await store.loadAll();
  } catch (e) {
    log?.call('settings: store unavailable, running on defaults without persistence ($e)');
    return HydratedSettings(store: InMemorySettingsStore(), initial: AppSettings.defaults, storeError: e);
  }

  final result = AppSettings.load(raw);
  if (result.repaired) {
    log?.call('settings: repaired on load: ${result.repairs.join(', ')}');
    for (final repair in result.repairs) {
      try {
        await store.write(repair.key, repair.after);
      } catch (e) {
        log?.call('settings: could not write back ${repair.key} ($e)');
      }
    }
  }
  return HydratedSettings(store: store, initial: result.settings, repairs: result.repairs);
}
