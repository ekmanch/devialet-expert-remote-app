import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:devialet_expert_remote_app/domain/settings/settings_store.dart';

void main() {
  group('InMemorySettingsStore', () {
    test('write / read / remove and the write log', () async {
      final store = InMemorySettingsStore({'a': 1});
      await store.write('b', 2.5);
      await store.write('a', null);
      await store.remove('zzz');
      expect(await store.loadAll(), {'b': 2.5});
      expect(store.writeLog, ['b', 'a', 'zzz']);
    });
  });

  group('SharedPreferencesSettingsStore (the only test that touches the plugin)', () {
    test('loads the seeded values and reads back every typed write', () async {
      SharedPreferences.setMockInitialValues({'seeded': 'yes'});
      final store = SharedPreferencesSettingsStore(await SharedPreferences.getInstance());
      expect(await store.loadAll(), {'seeded': 'yes'});
      await store.write('d', -40.0);
      await store.write('i', 3);
      await store.write('b', true);
      await store.write('s', 'x');
      expect(await store.loadAll(), {'seeded': 'yes', 'd': -40.0, 'i': 3, 'b': true, 's': 'x'});
      await store.remove('seeded');
      await store.write('s', null);
      expect(await store.loadAll(), {'d': -40.0, 'i': 3, 'b': true});
    });

    test('an unsupported type is an ArgumentError, not a silent drop', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesSettingsStore(await SharedPreferences.getInstance());
      expect(() => store.write('l', [1, 2]), throwsArgumentError);
    });
  });
}
