import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/hydrated_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_store.dart';

/// A disposable settings instance for tests: nothing touches the real
/// store (checklist 19).
HydratedSettings testHydrated({InMemorySettingsStore? store, AppSettings? initial, Object? storeError}) =>
    HydratedSettings(
      store: store ?? InMemorySettingsStore(),
      initial: initial ?? AppSettings.defaults,
      storeError: storeError,
    );
