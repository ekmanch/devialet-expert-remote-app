import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_settings.dart';
import 'hydrated_settings.dart';
import 'settings_store.dart';

/// Why a limits write was or wasn't applied — Task 3.4.4's UI "refuses"
/// with a reason rather than silently no-oping.
enum SetLimitsResult { applied, unchanged, refusedOutOfRange, refusedGap }

/// The owner of [AppSettings] (Task 3.3.1): controls emit intents, this
/// writes the value back (checklist 9); every change is stored (checklist
/// 8). Each intent updates state synchronously, then persists the
/// changed keys in a constraint-safe order (checklist 10); a failed write
/// keeps the in-memory value and is recorded in [lastWriteError].
/// The most recent persistence failure as observable state (Task 3.4.12):
/// the Settings screen shows a note while it is set. Mirrors
/// [SettingsNotifier.lastWriteError].
class SettingsWriteError extends Notifier<Object?> {
  @override
  Object? build() => null;

  void record(Object error) => state = error;
}

final settingsWriteErrorProvider = NotifierProvider<SettingsWriteError, Object?>(SettingsWriteError.new);

class SettingsNotifier extends Notifier<AppSettings> {
  late SettingsStore _store;

  /// The most recent persistence failure, if any; Task 3.4.x surfaces it.
  Object? lastWriteError;

  @override
  AppSettings build() {
    final hydrated = ref.watch(hydratedSettingsProvider);
    _store = hydrated.store;
    return hydrated.initial;
  }

  /// Both limits validated together: range, then the 1 dB gap. When both
  /// change, the on-disk order widens first (the lower floor before the
  /// ceiling if the floor drops, else the ceiling first) so a crash
  /// between the two writes never leaves an invalid pair for the next load.
  SetLimitsResult setVolumeLimits({double? floorDb, double? ceilingDb}) {
    final floor = floorDb ?? state.floorDb;
    final ceiling = ceilingDb ?? state.ceilingDb;
    if (!VolumeLimitRules.inRange(floor) || !VolumeLimitRules.inRange(ceiling)) {
      return SetLimitsResult.refusedOutOfRange;
    }
    if (ceiling - floor < VolumeLimitRules.minGapDb) return SetLimitsResult.refusedGap;
    if (floor == state.floorDb && ceiling == state.ceilingDb) return SetLimitsResult.unchanged;
    _commit(state.copyWith(floorDb: floor, ceilingDb: ceiling), _limitWrites(floor, ceiling));
    return SetLimitsResult.applied;
  }

  List<(String, Object?)> _limitWrites(double floor, double ceiling) {
    final floorWrite = (SettingsKeys.volumeFloorDb, floor as Object?);
    final ceilingWrite = (SettingsKeys.volumeCeilingDb, ceiling as Object?);
    final floorChanged = floor != state.floorDb;
    final ceilingChanged = ceiling != state.ceilingDb;
    if (floorChanged && ceilingChanged) {
      return floor < state.floorDb ? [floorWrite, ceilingWrite] : [ceilingWrite, floorWrite];
    }
    return [if (floorChanged) floorWrite, if (ceilingChanged) ceilingWrite];
  }

  /// Not constrained to the current limits: clamped at use
  /// (`AmpState.startupVolumeTarget`), so a later limit change never has
  /// to rewrite it. Returns false when outside −96..0.
  bool setStartupVolumeDb(double db) {
    if (!VolumeLimitRules.inRange(db)) return false;
    if (db != state.startupVolumeDb) {
      _commit(state.copyWith(startupVolumeDb: db), [(SettingsKeys.startupVolumeDb, db)]);
    }
    return true;
  }

  void setStepDb(VolumeStepDb step) {
    if (step == state.stepDb) return;
    _commit(state.copyWith(stepDb: step), [(SettingsKeys.volumeStepDb, step.db)]);
  }

  void setThemeMode(AppThemeMode mode) {
    if (mode == state.themeMode) return;
    _commit(state.copyWith(themeMode: mode), [(SettingsKeys.themeMode, mode.name)]);
  }

  /// "chose X" (`ip`, true), "chose None" (`null`, true); `explicit: false`
  /// only ever means the never-chosen state and carries no ip.
  void setSelection({required String? ip, required bool explicit}) {
    final effectiveIp = explicit ? ip : null;
    final next = state.copyWith(selectedIp: effectiveIp, hasExplicitSelection: explicit);
    if (next == state) return;
    _commit(next, [
      if (effectiveIp != state.selectedIp) (SettingsKeys.selectedIp, effectiveIp),
      if (explicit != state.hasExplicitSelection) (SettingsKeys.hasExplicitSelection, explicit),
    ]);
  }

  /// Limits (widen-first), startup, step, theme. The selection is not a
  /// preference and is left alone.
  void restoreDefaults() {
    const d = AppSettings.defaults;
    final writes = <(String, Object?)>[
      ..._limitWrites(d.floorDb, d.ceilingDb),
      if (state.startupVolumeDb != d.startupVolumeDb) (SettingsKeys.startupVolumeDb, d.startupVolumeDb),
      if (state.stepDb != d.stepDb) (SettingsKeys.volumeStepDb, d.stepDb.db),
      if (state.themeMode != d.themeMode) (SettingsKeys.themeMode, d.themeMode.name),
    ];
    final next = state.copyWith(
      floorDb: d.floorDb,
      ceilingDb: d.ceilingDb,
      startupVolumeDb: d.startupVolumeDb,
      stepDb: d.stepDb,
      themeMode: d.themeMode,
    );
    if (next == state) return;
    _commit(next, writes);
  }

  void _commit(AppSettings next, List<(String, Object?)> writes) {
    state = next;
    unawaited(_persist(writes));
  }

  Future<void> _persist(List<(String, Object?)> writes) async {
    for (final (key, value) in writes) {
      try {
        await _store.write(key, value);
      } catch (e) {
        lastWriteError = e;
        ref.read(settingsWriteErrorProvider.notifier).record(e);
      }
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
