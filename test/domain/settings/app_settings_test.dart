import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';

void main() {
  const nonDefault = AppSettings(
    floorDb: -60,
    ceilingDb: -20,
    startupVolumeDb: -35,
    stepDb: VolumeStepDb.half,
    themeMode: AppThemeMode.dark,
    selectedIp: '192.0.2.22',
    hasExplicitSelection: true,
  );

  group('round trip', () {
    test('defaults, a non-default instance and "chose None" survive toMap → load with no repairs', () {
      for (final s in [
        AppSettings.defaults,
        nonDefault,
        AppSettings.defaults.copyWith(selectedIp: null, hasExplicitSelection: true),
      ]) {
        final r = AppSettings.load(s.toMap());
        expect(r.settings, s);
        expect(r.repairs, isEmpty);
      }
    });

    test('an empty map is the defaults with no repairs', () {
      final r = AppSettings.load(const {});
      expect(r.settings, AppSettings.defaults);
      expect(r.repaired, isFalse);
    });
  });

  group('typed read', () {
    test('mistyped values fall back to the default with one repair per key', () {
      final r = AppSettings.load({
        SettingsKeys.volumeFloorDb: 'abc',
        SettingsKeys.hasExplicitSelection: 1,
        SettingsKeys.themeMode: 3,
        SettingsKeys.volumeStepDb: 'x',
        SettingsKeys.selectedIp: 42,
      });
      expect(r.settings, AppSettings.defaults);
      expect(r.repairs.map((x) => x.key), [
        SettingsKeys.volumeStepDb,
        SettingsKeys.themeMode,
        SettingsKeys.hasExplicitSelection,
        SettingsKeys.selectedIp,
        SettingsKeys.volumeFloorDb,
      ]);
    });

    test('an int for a dB key is a legitimate widening, not a repair', () {
      final r = AppSettings.load({SettingsKeys.startupVolumeDb: -30});
      expect(r.settings.startupVolumeDb, -30.0);
      expect(r.repairs, isEmpty);
    });

    test('unknown step or theme values fall back and are repaired', () {
      final r = AppSettings.load({SettingsKeys.volumeStepDb: 0.7, SettingsKeys.themeMode: 'blue'});
      expect(r.settings.stepDb, VolumeStepDb.one);
      expect(r.settings.themeMode, AppThemeMode.system);
      expect(r.repairs.length, 2);
    });
  });

  group('heal (3.3.2 / 3.4.10)', () {
    test('out-of-range or non-finite dB values become that field\'s default', () {
      for (final bad in [-97.0, 0.5, double.nan, double.infinity]) {
        final r = AppSettings.load({SettingsKeys.startupVolumeDb: bad});
        expect(r.settings.startupVolumeDb, -40.0, reason: '$bad');
        expect(r.repairs.single.key, SettingsKeys.startupVolumeDb);
      }
    });

    test('an inverted, equal or too-close pair heals to −40/−39 as a unit', () {
      for (final (floor, ceiling) in [(-10.0, -50.0), (-30.0, -30.0), (-30.0, -29.5)]) {
        final r = AppSettings.load({SettingsKeys.volumeFloorDb: floor, SettingsKeys.volumeCeilingDb: ceiling});
        expect((r.settings.floorDb, r.settings.ceilingDb), (-40.0, -39.0), reason: '$floor/$ceiling');
        expect(r.repairs.map((x) => x.key), [SettingsKeys.volumeFloorDb, SettingsKeys.volumeCeilingDb]);
      }
      final ok = AppSettings.load({SettingsKeys.volumeFloorDb: -30.0, SettingsKeys.volumeCeilingDb: -29.0});
      expect((ok.settings.floorDb, ok.settings.ceilingDb), (-30.0, -29.0));
      expect(ok.repairs, isEmpty);
    });

    test('values are brought into range before the pair is judged (checklist 10)', () {
      final r = AppSettings.load({SettingsKeys.volumeFloorDb: -200.0, SettingsKeys.volumeCeilingDb: -5.0});
      expect((r.settings.floorDb, r.settings.ceilingDb), (-50.0, -5.0));
      expect(r.repairs.map((x) => x.key), [SettingsKeys.volumeFloorDb]);
    });

    test('startup is not healed against the pair (clamped at use instead)', () {
      final r = AppSettings.load({
        SettingsKeys.volumeFloorDb: -30.0,
        SettingsKeys.volumeCeilingDb: -20.0,
        SettingsKeys.startupVolumeDb: -50.0,
      });
      expect(r.settings.startupVolumeDb, -50.0);
      expect(r.repairs, isEmpty);
    });

    test('an ip stored without the explicit flag is removed; an empty ip is None', () {
      final r = AppSettings.load({SettingsKeys.selectedIp: '192.0.2.22', SettingsKeys.hasExplicitSelection: false});
      expect(r.settings.selectedIp, isNull);
      expect(r.repairs.single, isA<SettingRepair>().having((x) => x.after, 'after', isNull));
      final e = AppSettings.load({SettingsKeys.selectedIp: '', SettingsKeys.hasExplicitSelection: true});
      expect(e.settings.selectedIp, isNull);
      expect(e.settings.hasExplicitSelection, isTrue);
    });
  });

  test('the default ceiling is −10 dB and is not silently regressed (gotcha #6, checklist 28)', () {
    // The wire clamp reads this value through DevialetClientCommandSink;
    // change it together with the mockup's range and the KDE widget's default.
    expect(AppSettings.defaults.ceilingDb, -10.0);
    expect(AppSettings.defaults.floorDb, -50.0);
    expect(AppSettings.defaults.startupVolumeDb, -40.0);
  });

  test('VolumeLimitRules.validPair truth table', () {
    expect(VolumeLimitRules.validPair(-50, -10), isTrue);
    expect(VolumeLimitRules.validPair(-30, -29), isTrue);
    expect(VolumeLimitRules.validPair(-30, -29.5), isFalse);
    expect(VolumeLimitRules.validPair(-10, -50), isFalse);
    expect(VolumeLimitRules.validPair(-97, -10), isFalse);
    expect(VolumeLimitRules.validPair(-50, 0.5), isFalse);
  });
}
