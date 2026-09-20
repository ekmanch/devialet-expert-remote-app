import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/hydrated_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_store.dart';

class _FailingWriteStore extends InMemorySettingsStore {
  _FailingWriteStore(super.initial);
  @override
  Future<void> write(String key, Object? value) async => throw const SettingsWriteException('disk full');
}

void main() {
  test('a valid store hydrates as stored with no repairs and no write-back', () async {
    final store = InMemorySettingsStore({SettingsKeys.volumeFloorDb: -60.0, SettingsKeys.volumeCeilingDb: -20.0});
    final h = await hydrateSettings(() async => store);
    expect(h.initial.floorDb, -60.0);
    expect(h.repairs, isEmpty);
    expect(store.writeLog, isEmpty);
    expect(h.storeUnavailable, isFalse);
  });

  test('an inverted pair is healed before anything binds and written back to the store', () async {
    final store = InMemorySettingsStore({SettingsKeys.volumeFloorDb: -10.0, SettingsKeys.volumeCeilingDb: -50.0});
    final logs = <String>[];
    final h = await hydrateSettings(() async => store, log: logs.add);
    expect((h.initial.floorDb, h.initial.ceilingDb), (-40.0, -39.0));
    expect(store.values[SettingsKeys.volumeFloorDb], -40.0);
    expect(store.values[SettingsKeys.volumeCeilingDb], -39.0);
    expect(logs.single, contains('repaired'));
  });

  test('a store that cannot be opened falls back to defaults on an in-memory store and says so', () async {
    final logs = <String>[];
    final h = await hydrateSettings(() async => throw StateError('no platform'), log: logs.add);
    expect(h.storeUnavailable, isTrue);
    expect(h.initial, AppSettings.defaults);
    expect(h.store, isA<InMemorySettingsStore>());
    expect(logs.single, contains('unavailable'));
  });

  test('a failed write-back is logged, the healed value is still used', () async {
    final store = _FailingWriteStore({SettingsKeys.startupVolumeDb: 5.0});
    final logs = <String>[];
    final h = await hydrateSettings(() async => store, log: logs.add);
    expect(h.initial.startupVolumeDb, -40.0);
    expect(logs.any((l) => l.contains('could not write back')), isTrue);
  });
}
