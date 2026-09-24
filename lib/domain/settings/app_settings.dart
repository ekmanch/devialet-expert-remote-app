/// The one typed settings object (Task 3.3.1): named keys, defaults and
/// validation in one place. Pure Dart. Persisted through
/// `settings_store.dart`, owned by `settings_owner.dart`, hydrated and
/// self-healed before anything binds by `hydrated_settings.dart`.
library;

enum AppThemeMode { system, dark, light }

/// Task 3.4.9: 0.5 / 1 / 2 dB, default 1.
enum VolumeStepDb {
  half(0.5),
  one(1.0),
  two(2.0);

  const VolumeStepDb(this.db);

  final double db;

  static VolumeStepDb? fromDb(double db) {
    for (final step in values) {
      if (step.db == db) return step;
    }
    return null;
  }
}

/// Storage keys. The plugin adds its own `flutter.` prefix on Android;
/// never reference that in code.
abstract final class SettingsKeys {
  static const String volumeFloorDb = 'volume_floor_db';
  static const String volumeCeilingDb = 'volume_ceiling_db';
  static const String startupVolumeDb = 'startup_volume_db';
  static const String volumeStepDb = 'volume_step_db';
  static const String themeMode = 'theme_mode';

  /// Absent == "None" or never chosen; [hasExplicitSelection] tells which.
  static const String selectedIp = 'selected_ip';
  static const String hasExplicitSelection = 'has_explicit_selection';

  static const List<String> all = [
    volumeFloorDb,
    volumeCeilingDb,
    startupVolumeDb,
    volumeStepDb,
    themeMode,
    selectedIp,
    hasExplicitSelection,
  ];
}

/// The numbers behind Tasks 3.4.7 / 3.4.10, in one place (checklist 28).
abstract final class VolumeLimitRules {
  static const double minDb = -96.0;
  static const double maxDb = 0.0;
  static const double minGapDb = 1.0;

  /// An invalid stored pair heals to this (same as the KDE widget).
  static const double healedFloorDb = -40.0;
  static const double healedCeilingDb = -39.0;

  static bool inRange(double db) => db.isFinite && db >= minDb && db <= maxDb;

  static bool validPair(double floorDb, double ceilingDb) =>
      inRange(floorDb) && inRange(ceilingDb) && ceilingDb - floorDb >= minGapDb;
}

/// One value the loader or the healer changed (or removed: `after == null`).
class SettingRepair {
  const SettingRepair(this.key, this.before, this.after);

  final String key;
  final Object? before;
  final Object? after;

  @override
  String toString() => '$key: $before -> $after';
}

class HealResult {
  const HealResult(this.settings, this.repairs);

  final AppSettings settings;
  final List<SettingRepair> repairs;

  bool get repaired => repairs.isNotEmpty;
}

const Object _unset = Object();

class AppSettings {
  const AppSettings({
    required this.floorDb,
    required this.ceilingDb,
    required this.startupVolumeDb,
    required this.stepDb,
    required this.themeMode,
    required this.selectedIp,
    required this.hasExplicitSelection,
  });

  /// Owner decisions 2026-09-14 (limits, startup) and 3.4.9 (step). The
  /// ceiling is the wire-side `maxDb` too: the command sink reads it from
  /// the settings at send time (Task 3.4.7 / 1.1.3, done 2026-09-20).
  static const AppSettings defaults = AppSettings(
    floorDb: -50.0,
    ceilingDb: -10.0,
    startupVolumeDb: -40.0,
    stepDb: VolumeStepDb.one,
    themeMode: AppThemeMode.system,
    selectedIp: null,
    hasExplicitSelection: false,
  );

  /// UI-only; never reaches the wire (Task 3.4.8).
  final double floorDb;
  final double ceilingDb;
  final double startupVolumeDb;
  final VolumeStepDb stepDb;

  /// Stored since 3.3.x, consumed by Task 3.4.x.
  final AppThemeMode themeMode;

  /// "chose X" (ip, true), "chose None" (null, true), "never chose"
  /// (null, false) — three distinct states (checklist 4).
  final String? selectedIp;
  final bool hasExplicitSelection;

  AppSettings copyWith({
    double? floorDb,
    double? ceilingDb,
    double? startupVolumeDb,
    VolumeStepDb? stepDb,
    AppThemeMode? themeMode,
    Object? selectedIp = _unset,
    bool? hasExplicitSelection,
  }) {
    return AppSettings(
      floorDb: floorDb ?? this.floorDb,
      ceilingDb: ceilingDb ?? this.ceilingDb,
      startupVolumeDb: startupVolumeDb ?? this.startupVolumeDb,
      stepDb: stepDb ?? this.stepDb,
      themeMode: themeMode ?? this.themeMode,
      selectedIp: identical(selectedIp, _unset) ? this.selectedIp : selectedIp as String?,
      hasExplicitSelection: hasExplicitSelection ?? this.hasExplicitSelection,
    );
  }

  Map<String, Object?> toMap() => {
    SettingsKeys.volumeFloorDb: floorDb,
    SettingsKeys.volumeCeilingDb: ceilingDb,
    SettingsKeys.startupVolumeDb: startupVolumeDb,
    SettingsKeys.volumeStepDb: stepDb.db,
    SettingsKeys.themeMode: themeMode.name,
    if (selectedIp != null) SettingsKeys.selectedIp: selectedIp,
    SettingsKeys.hasExplicitSelection: hasExplicitSelection,
  };

  /// Typed read of a raw store map (a missing key is its default and not
  /// a repair; a mistyped or unknown value is the default *and* a
  /// repair), followed by [healed].
  static HealResult load(Map<String, Object?> raw) {
    final repairs = <SettingRepair>[];

    double readDb(String key, double fallback) {
      final v = raw[key];
      if (v is num) return v.toDouble();
      if (v != null) repairs.add(SettingRepair(key, v, fallback));
      return fallback;
    }

    final rawStep = raw[SettingsKeys.volumeStepDb];
    var step = defaults.stepDb;
    if (rawStep is num) {
      final parsed = VolumeStepDb.fromDb(rawStep.toDouble());
      if (parsed == null) repairs.add(SettingRepair(SettingsKeys.volumeStepDb, rawStep, step.db));
      step = parsed ?? step;
    } else if (rawStep != null) {
      repairs.add(SettingRepair(SettingsKeys.volumeStepDb, rawStep, step.db));
    }

    final rawTheme = raw[SettingsKeys.themeMode];
    var theme = defaults.themeMode;
    if (rawTheme is String) {
      final parsed = AppThemeMode.values.where((m) => m.name == rawTheme).firstOrNull;
      if (parsed == null) repairs.add(SettingRepair(SettingsKeys.themeMode, rawTheme, theme.name));
      theme = parsed ?? theme;
    } else if (rawTheme != null) {
      repairs.add(SettingRepair(SettingsKeys.themeMode, rawTheme, theme.name));
    }

    final rawFlag = raw[SettingsKeys.hasExplicitSelection];
    var flag = defaults.hasExplicitSelection;
    if (rawFlag is bool) {
      flag = rawFlag;
    } else if (rawFlag != null) {
      repairs.add(SettingRepair(SettingsKeys.hasExplicitSelection, rawFlag, flag));
    }

    final rawIp = raw[SettingsKeys.selectedIp];
    String? ip;
    if (rawIp is String && rawIp.isNotEmpty) {
      ip = rawIp;
    } else if (rawIp != null) {
      repairs.add(SettingRepair(SettingsKeys.selectedIp, rawIp, null));
    }

    final loaded = AppSettings(
      floorDb: readDb(SettingsKeys.volumeFloorDb, defaults.floorDb),
      ceilingDb: readDb(SettingsKeys.volumeCeilingDb, defaults.ceilingDb),
      startupVolumeDb: readDb(SettingsKeys.startupVolumeDb, defaults.startupVolumeDb),
      stepDb: step,
      themeMode: theme,
      selectedIp: ip,
      hasExplicitSelection: flag,
    );
    final healed = loaded.healed();
    return HealResult(healed.settings, [...repairs, ...healed.repairs]);
  }

  /// Self-heal (Task 3.3.2 hook, rules from 3.4.7 / 3.4.10), in a safe
  /// order (checklist 10): each dB value into range first, then the pair
  /// as a unit, then the selection pair.
  ///
  /// | rule | condition | result |
  /// |---|---|---|
  /// | 1 | floor / ceiling / startup not finite or outside −96..0 | that field's default |
  /// | 2 | ceiling − floor < 1 dB (inverted, equal, too close) | floor −40, ceiling −39 |
  /// | 3 | startup vs. the pair | untouched — clamped at use (`AmpState.startupVolumeTarget`) |
  /// | 4 | an ip stored with `hasExplicitSelection == false` | ip removed (never-chosen carries no ip) |
  HealResult healed() {
    final repairs = <SettingRepair>[];
    var floor = floorDb;
    var ceiling = ceilingDb;
    var startup = startupVolumeDb;
    var ip = selectedIp;

    if (!VolumeLimitRules.inRange(floor)) {
      repairs.add(SettingRepair(SettingsKeys.volumeFloorDb, floor, defaults.floorDb));
      floor = defaults.floorDb;
    }
    if (!VolumeLimitRules.inRange(ceiling)) {
      repairs.add(SettingRepair(SettingsKeys.volumeCeilingDb, ceiling, defaults.ceilingDb));
      ceiling = defaults.ceilingDb;
    }
    if (!VolumeLimitRules.inRange(startup)) {
      repairs.add(SettingRepair(SettingsKeys.startupVolumeDb, startup, defaults.startupVolumeDb));
      startup = defaults.startupVolumeDb;
    }
    if (ceiling - floor < VolumeLimitRules.minGapDb) {
      repairs.add(SettingRepair(SettingsKeys.volumeFloorDb, floor, VolumeLimitRules.healedFloorDb));
      repairs.add(SettingRepair(SettingsKeys.volumeCeilingDb, ceiling, VolumeLimitRules.healedCeilingDb));
      floor = VolumeLimitRules.healedFloorDb;
      ceiling = VolumeLimitRules.healedCeilingDb;
    }
    if (ip != null && !hasExplicitSelection) {
      repairs.add(SettingRepair(SettingsKeys.selectedIp, ip, null));
      ip = null;
    }

    final settings = AppSettings(
      floorDb: floor,
      ceilingDb: ceiling,
      startupVolumeDb: startup,
      stepDb: stepDb,
      themeMode: themeMode,
      selectedIp: ip,
      hasExplicitSelection: hasExplicitSelection,
    );
    return HealResult(settings, repairs);
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.floorDb == floorDb &&
      other.ceilingDb == ceilingDb &&
      other.startupVolumeDb == startupVolumeDb &&
      other.stepDb == stepDb &&
      other.themeMode == themeMode &&
      other.selectedIp == selectedIp &&
      other.hasExplicitSelection == hasExplicitSelection;

  @override
  int get hashCode =>
      Object.hash(floorDb, ceilingDb, startupVolumeDb, stepDb, themeMode, selectedIp, hasExplicitSelection);

  @override
  String toString() => 'AppSettings(${toMap()})';
}
