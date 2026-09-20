import 'package:shared_preferences/shared_preferences.dart';

/// Key/value persistence behind the settings owner. Values are the plain
/// types the plugin supports: `double`, `int`, `bool`, `String`; `null`
/// removes the key.
abstract interface class SettingsStore {
  Future<Map<String, Object?>> loadAll();

  Future<void> write(String key, Object? value);

  Future<void> remove(String key);
}

class SettingsWriteException implements Exception {
  const SettingsWriteException(this.key, [this.cause]);

  final String key;
  final Object? cause;

  @override
  String toString() => 'SettingsWriteException($key${cause == null ? '' : ': $cause'})';
}

/// The disposable instance for tests and the fallback when the real store
/// cannot be opened (checklist 19: nothing in a test touches the real
/// store).
class InMemorySettingsStore implements SettingsStore {
  InMemorySettingsStore([Map<String, Object?> initial = const {}]) : values = Map.of(initial);

  final Map<String, Object?> values;

  /// Keys in write order — lets tests assert the widen-first ordering.
  final List<String> writeLog = [];

  @override
  Future<Map<String, Object?>> loadAll() async => Map.of(values);

  @override
  Future<void> write(String key, Object? value) async {
    writeLog.add(key);
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> remove(String key) => write(key, null);
}

/// Task 3.3.0: app-local storage via the `shared_preferences` plugin —
/// `SharedPreferences` on Android, `UserDefaults` on iOS, the footprint
/// the Kotlin app used. The only file that imports the plugin.
class SharedPreferencesSettingsStore implements SettingsStore {
  SharedPreferencesSettingsStore(this._prefs);

  static Future<SharedPreferencesSettingsStore> open() async =>
      SharedPreferencesSettingsStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  @override
  Future<Map<String, Object?>> loadAll() async => {for (final key in _prefs.getKeys()) key: _prefs.get(key)};

  @override
  Future<void> write(String key, Object? value) async {
    final bool ok;
    try {
      ok = switch (value) {
        null => await _prefs.remove(key),
        final double v => await _prefs.setDouble(key, v),
        final int v => await _prefs.setInt(key, v),
        final bool v => await _prefs.setBool(key, v),
        final String v => await _prefs.setString(key, v),
        _ => throw ArgumentError.value(value, 'value', 'unsupported settings type for $key'),
      };
    } on ArgumentError {
      rethrow;
    } catch (e) {
      throw SettingsWriteException(key, e);
    }
    if (!ok) throw SettingsWriteException(key);
  }

  @override
  Future<void> remove(String key) => write(key, null);
}
