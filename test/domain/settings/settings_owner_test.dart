import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/hydrated_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_owner.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_store.dart';

import '../support/settings_support.dart';

class _ThrowingStore extends InMemorySettingsStore {
  @override
  Future<void> write(String key, Object? value) async => throw const SettingsWriteException('nope');
}

void main() {
  late InMemorySettingsStore store;

  ProviderContainer make({AppSettings? initial, InMemorySettingsStore? withStore}) {
    store = withStore ?? InMemorySettingsStore();
    return ProviderContainer.test(
      overrides: [hydratedSettingsProvider.overrideWithValue(testHydrated(store: store, initial: initial))],
    );
  }

  SettingsNotifier owner(ProviderContainer c) => c.read(settingsProvider.notifier);
  AppSettings state(ProviderContainer c) => c.read(settingsProvider);
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('every intent persists to its exact key (checklist 8)', () async {
    final c = make();
    expect(owner(c).setVolumeLimits(floorDb: -60, ceilingDb: -20), SetLimitsResult.applied);
    expect(owner(c).setStartupVolumeDb(-35), isTrue);
    owner(c).setStepDb(VolumeStepDb.two);
    owner(c).setThemeMode(AppThemeMode.dark);
    owner(c).setSelection(ip: '192.0.2.22', explicit: true);
    await settle();
    expect(await store.loadAll(), {
      SettingsKeys.volumeFloorDb: -60.0,
      SettingsKeys.volumeCeilingDb: -20.0,
      SettingsKeys.startupVolumeDb: -35.0,
      SettingsKeys.volumeStepDb: 2.0,
      SettingsKeys.themeMode: 'dark',
      SettingsKeys.selectedIp: '192.0.2.22',
      SettingsKeys.hasExplicitSelection: true,
    });
    expect(state(c), AppSettings.load(await store.loadAll()).settings, reason: 'read back == in memory');
  });

  test('refused writes change neither state nor store', () async {
    final c = make();
    expect(owner(c).setVolumeLimits(floorDb: -20, ceilingDb: -20), SetLimitsResult.refusedGap);
    expect(owner(c).setVolumeLimits(floorDb: -100), SetLimitsResult.refusedOutOfRange);
    expect(owner(c).setStartupVolumeDb(1), isFalse);
    await settle();
    expect(state(c), AppSettings.defaults);
    expect(store.writeLog, isEmpty);
  });

  test('"chose None" writes the flag and removes the ip; an unchanged value writes nothing', () async {
    final c = make();
    owner(c).setSelection(ip: '192.0.2.22', explicit: true);
    owner(c).setSelection(ip: null, explicit: true);
    await settle();
    expect(store.values.containsKey(SettingsKeys.selectedIp), isFalse);
    expect(store.values[SettingsKeys.hasExplicitSelection], true);
    final writes = store.writeLog.length;
    owner(c).setSelection(ip: null, explicit: true);
    owner(c).setThemeMode(AppThemeMode.system);
    expect(owner(c).setVolumeLimits(floorDb: -50), SetLimitsResult.unchanged);
    await settle();
    expect(store.writeLog.length, writes);
  });

  test('restoreDefaults writes limits widen-first, then startup/step/theme, and leaves the selection alone', () async {
    for (final (floor, ceiling, expectedOrder) in [
      (-45.0, -12.0, [SettingsKeys.volumeFloorDb, SettingsKeys.volumeCeilingDb]),
      (-60.0, -40.0, [SettingsKeys.volumeCeilingDb, SettingsKeys.volumeFloorDb]),
    ]) {
      final c = make(
        initial: AppSettings.defaults.copyWith(
          floorDb: floor,
          ceilingDb: ceiling,
          startupVolumeDb: -30,
          stepDb: VolumeStepDb.half,
          themeMode: AppThemeMode.light,
          selectedIp: '192.0.2.22',
          hasExplicitSelection: true,
        ),
      );
      owner(c).restoreDefaults();
      await settle();
      expect(store.writeLog, [
        ...expectedOrder,
        SettingsKeys.startupVolumeDb,
        SettingsKeys.volumeStepDb,
        SettingsKeys.themeMode,
      ]);
      expect(state(c).selectedIp, '192.0.2.22');
      expect(state(c).copyWith(selectedIp: null, hasExplicitSelection: false), AppSettings.defaults);
    }
  });

  test('a failing store keeps the in-memory value and records the error', () async {
    final c = make(withStore: _ThrowingStore());
    owner(c).setThemeMode(AppThemeMode.dark);
    await settle();
    expect(state(c).themeMode, AppThemeMode.dark);
    expect(owner(c).lastWriteError, isA<SettingsWriteException>());
    expect(c.read(settingsWriteErrorProvider), isA<SettingsWriteException>(), reason: 'observable for the UI');
  });
}
