import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../networking/devialet_client.dart';
import 'amp_command_sink.dart';
import 'amp_state.dart';
import 'amp_trace.dart';
import 'amp_tracker.dart';
import 'control_view_state.dart';
import 'devialet_client_provider.dart';
import 'monotonic_clock.dart';
import 'settings/app_settings.dart';
import 'settings/settings_owner.dart';

/// The one owner of live amp state (TODO 3.0.0; `docs/architecture.md`).
///
/// Ingests every status broadcast into [AmpState.amps] keyed by sender IP,
/// re-evaluates staleness and pending deadlines on the 1 s tick, holds the
/// selection, and applies every intent as a synchronous optimistic write
/// through the pending mask before sending. Views read the derived
/// [controlViewStateProvider]; nothing keeps a private copy.
class AmpStateOwner extends Notifier<AmpState> {
  late MonotonicClock _clock;
  late AmpCommandSink _sink;
  late AmpTrace _trace;

  /// Task 3.6.6: the last `(selected ip, clamp-eligible)` seen after a
  /// write; a false→true edge (connection landing, power reaching On, the
  /// boot follow-ups finishing) or an ip change while eligible schedules
  /// one limit-clamp evaluation.
  late ({String? ip, bool eligible}) _clampKey;
  bool _clampScheduled = false;

  @override
  AmpState build() {
    _clock = ref.watch(monotonicClockProvider);
    _sink = ref.watch(ampCommandSinkProvider);
    _trace = ref.watch(ampTraceProvider);
    // Persisted settings (Task 3.3.x): read once for the initial state,
    // then *listen* — a watch would rebuild this notifier and drop its
    // subscriptions. Only the volume fields are applied from the listener;
    // the selection is written by this owner itself, so there is no loop.
    final settings = ref.read(settingsProvider);
    ref.listen(settingsProvider, (_, next) {
      final limitsChanged = state.floorDb != next.floorDb || state.ceilingDb != next.ceilingDb;
      final view = _viewIfTracing;
      state = state.copyWith(
        floorDb: next.floorDb,
        ceilingDb: next.ceilingDb,
        startupVolumeDb: next.startupVolumeDb,
        stepDb: next.stepDb.db,
      );
      _afterWrite(view);
      if (limitsChanged) _scheduleLimitClamp();
    });
    final client = ref.watch(devialetClientProvider);
    client.startListening();
    final reports = client.statusReports.listen(ingest);
    final ticks = ref.watch(staleTickProvider).listen((_) => _onTick());
    ref.onDispose(() {
      reports.cancel();
      ticks.cancel();
      client.stopListening();
    });
    final initial = AmpState.initial.copyWith(
      now: _clock.now(),
      selectedIp: settings.selectedIp,
      hasExplicitSelection: settings.hasExplicitSelection,
      floorDb: settings.floorDb,
      ceilingDb: settings.ceilingDb,
      startupVolumeDb: settings.startupVolumeDb,
      stepDb: settings.stepDb.db,
    );
    _clampKey = _clampKeyOf(initial);
    return initial;
  }

  Duration get _now => _clock.now();

  ControlViewState get _view => deriveControlView(state);

  // ---- Inputs

  /// The single entry point for broadcasts: the socket, the debug
  /// simulated amp and test seeding all come through here.
  void ingest(AmpStatusReport report) {
    final ip = report.senderIp;
    final before = _trace.enabled ? state.amps[ip] : null;
    final view = _viewIfTracing;
    state = state.ingest(report, _now);
    if (_trace.enabled) {
      final after = state.amps[ip]!;
      if (ip == state.effectiveIp &&
          (before == null ||
              before.status.isPoweredOn != after.status.isPoweredOn ||
              before.status.volumeRaw != after.status.volumeRaw)) {
        _trace('rx', {
          'ip': ip,
          'power': after.status.isPoweredOn ? 'on' : 'off',
          'raw': after.status.volumeRaw,
          'db': after.status.volumeDb,
        });
      }
      _traceBoot(before, after);
    }
    _afterWrite(view);
    _runBootFollowUps();
  }

  void _onTick() {
    final before = _trace.enabled
        ? {
            for (final e in state.amps.entries)
              if (e.value.boot != null || e.value.pendingVolumeDb != null) e.key: e.value,
          }
        : const <String, TrackedAmp>{};
    final view = _viewIfTracing;
    state = state.tick(_now);
    for (final e in before.entries) {
      _traceBoot(e.value, state.amps[e.key]);
    }
    _afterWrite(view);
    _runBootFollowUps();
  }

  // ---- After every state write

  /// Runs after **every** `state =` in this class: the `view` trace (when
  /// tracing) and the limit-clamp edge detector (Task 3.6.6, checklist 11:
  /// re-trigger on every input that can complete late — a broadcast, a
  /// tick, a rollback, a selection change — not only on the setting that
  /// changed). One place, so a new write site cannot forget either.
  void _afterWrite(ControlViewState? viewBefore) {
    _traceViewChange(viewBefore);
    final key = _clampKeyOf(state);
    final previous = _clampKey;
    _clampKey = key;
    if (key.eligible && (!previous.eligible || previous.ip != key.ip)) _scheduleLimitClamp();
  }

  // ---- Debug trace (Task 3.5.2; `docs/architecture.md`, "Debug trace").
  // Diffs are computed only while tracing; release builds skip all of it.

  ControlViewState? get _viewIfTracing => _trace.enabled ? _view : null;

  /// The *displayed* values, from the same derivation the UI renders.
  void _traceViewChange(ControlViewState? before) {
    if (before == null) return;
    final after = _view;
    if (after.power == before.power &&
        after.volumeDb == before.volumeDb &&
        after.isMuted == before.isMuted &&
        after.hasAmp == before.hasAmp) {
      return;
    }
    _trace('view', {'power': after.power.name, 'db': after.volumeDb, 'muted': after.isMuted, 'hasAmp': after.hasAmp});
  }

  /// Boot-record and hold transitions between two snapshots of one amp.
  /// The release reason re-derives `PendingValue.isConfirmedBy` (exact
  /// equality on the decoded dB) for reporting only; `resolvePending`
  /// stays the one implementation.
  void _traceBoot(TrackedAmp? before, TrackedAmp? after) {
    if (after == null) return;
    final b = before?.boot;
    final a = after.boot;
    if (b == null && a != null && a.isConfirmed) {
      _trace('boot observed-external', {'ip': after.ip, 'target': a.target});
    } else if (b != null && !b.isConfirmed && a != null && a.isConfirmed) {
      _trace('boot confirmed', {
        'ip': after.ip,
        'target': a.target,
        'sendAtMs': kStartupVolumeDelay.inMilliseconds,
        'holdUntilMs': kBootHold.inMilliseconds,
      });
    } else if (b != null && !b.isConfirmed && a == null) {
      _trace('boot timeout', {'ip': after.ip});
    }
    final held = before?.pendingVolumeDb;
    if (held != null && b != null && b.isConfirmed && after.pendingVolumeDb == null) {
      _trace('hold released', {
        'ip': after.ip,
        'reason': after.status.volumeDb == held.value ? 'confirmed' : 'fallback',
        'sinceOnMs': (_now - b.confirmedAt!).inMilliseconds,
        'raw': after.status.volumeRaw,
        'db': after.status.volumeDb,
      });
    }
  }

  /// Task 3.2.2: for every amp whose self-initiated boot has been
  /// confirmed for at least [kStartupVolumeDelay], send the startup volume
  /// once. Runs after every ingest and tick (≤ 200 ms slack at 5 Hz, on
  /// the safe side of gotcha #9). Per amp, not per selection: the amp the
  /// user booted gets its correction even if the selection moved. Not a
  /// user entry point, so not gated by `commandsAllowed`; a failed send
  /// drops the record and the hold so the amp's own value shows honestly —
  /// no retry. The target is clamped to the limits *in force at the send*
  /// (the record's target was clamped when the boot started, and a 16 s
  /// boot is long enough for a Settings change), so the post-boot limit
  /// clamp (3.6.6) is a no-op by construction. Never unmutes (3.7.1).
  void _runBootFollowUps() {
    final now = _now;
    for (final amp in state.amps.values.toList()) {
      final boot = amp.boot;
      if (boot == null || !boot.isConfirmed || boot.startupSent || now < boot.sendAt!) continue;
      final target = state.clampDb(boot.target);
      _trace('boot startup-send', {
        'ip': amp.ip,
        'target': target,
        'sinceOnMs': (now - boot.confirmedAt!).inMilliseconds,
      });
      // Flip `startupSent` and restart the hold's fallback from the send
      // (500 send + ~200 confirm + the late-application allowance); from
      // now on a matching broadcast is a real confirmation.
      _arm(
        amp.ip,
        (a) => a.copyWith(
          boot: a.boot?.copyWith(startupSent: true, target: target),
          pendingVolumeDb: PendingValue(target, now + kBootHold),
        ),
      );
      unawaited(
        _send(amp.ip, (s) => s.sendStartupVolume(amp.ip, target), (a) => a.copyWith(boot: null, pendingVolumeDb: null)),
      );
    }
  }

  // ---- Limit-change clamp (Task 3.6.6 / 3.4.13; KDE `applyImmediateClamp`)

  /// Eligible = the selected amp is reachable, On (masked power, so an
  /// optimistic Off counts as Off) and has no boot record: the follow-ups
  /// leave it at the clamped startup target, and a send inside gotcha #9's
  /// window would be dropped anyway.
  static ({String? ip, bool eligible}) _clampKeyOf(AmpState s) {
    final amp = s.selectedAmp;
    final eligible =
        amp != null && amp.isOnlineAt(s.now) && amp.powerPhaseAt(s.now) == PowerPhase.on && amp.boot == null;
    return (ip: s.effectiveIp, eligible: eligible);
  }

  /// Coalesces every trigger of one synchronous run (both limits written
  /// by one call, a broadcast that lands and confirms in the same tick)
  /// into a single evaluation at the end of the microtask queue; the
  /// evaluation re-reads [state], so it sees the final values.
  void _scheduleLimitClamp() {
    if (_clampScheduled) return;
    _clampScheduled = true;
    scheduleMicrotask(() {
      _clampScheduled = false;
      if (!ref.mounted) return;
      _applyLimitClamp();
    });
  }

  /// Nothing is sent when the displayed value is already in range, so the
  /// routine case (a limit widened, a reconnect) costs nothing on the
  /// wire. One evaluation per trigger and no retry: an ignored clamp is
  /// re-sent at the next trigger, never on a timer (KDE parity). Every
  /// armed pending value was clamped when it was armed, so "displayed in
  /// range" is the right no-op test even mid-mask: a pending *user* value
  /// that the new limits exclude must be clamped too.
  void _applyLimitClamp() {
    final ip = state.effectiveIp;
    final amp = state.selectedAmp;
    if (ip == null || amp == null || !_clampKeyOf(state).eligible) return;
    final shown = amp.displayedVolumeDb;
    if (state.inRange(shown)) return;
    final target = state.clampDb(shown);
    _trace('clamp', {'ip': ip, 'from': shown, 'to': target});
    unawaited(_writeVolume(ip, target, userIntent: false));
  }

  // ---- Selection (checklist 4: "chose None" ≠ "never chose")

  /// User intent: selects and **persists** (Task 3.9.1). `null` == None.
  void selectIp(String? ip) {
    seedSelection(ip);
    ref.read(settingsProvider.notifier).setSelection(ip: ip, explicit: true);
  }

  /// Seeding / debug seam: the same state change **without persisting**,
  /// so the simulated amp and test fixtures never write a TEST-NET address
  /// into the real store (checklist 19). The persisted path is [selectIp].
  void seedSelection(String? ip, {bool explicit = true}) {
    final view = _viewIfTracing;
    state = state.copyWith(selectedIp: ip, hasExplicitSelection: explicit);
    _afterWrite(view);
  }

  void selectAmp(AmpRef? amp) => selectIp(amp?.ip);

  /// A never-heard IP is a valid selection; it shows as not connected
  /// until a broadcast from it arrives (`docs/protocol.md`, "Multi-amp").
  void addManualAmp(String ip) => selectIp(ip);

  // ---- Seams for later tasks

  /// Task 3.9.5 (mDNS). Ignored for an amp never heard from.
  void setModelName(String ip, String? model) {
    final view = _viewIfTracing;
    state = state.updateAmp(ip, (a) => a.copyWith(modelName: model));
    _afterWrite(view);
  }

  /// Enters Booting for a self-initiated power-on (Task 3.2.0). A boot
  /// already in progress is not extended (repeated taps don't move the
  /// deadline), and an amp still *reporting* On gets no record: an
  /// unconfirmed optimistic Off must not be "confirmed" by a stale On.
  void markBooting(String ip, {Duration timeout = kBootTimeout}) {
    final target = state.startupVolumeTarget;
    final amp = state.amps[ip];
    if (_trace.enabled && amp != null && amp.boot == null && !amp.status.isPoweredOn) {
      _trace('boot booting', {'ip': ip, 'deadlineMs': timeout.inMilliseconds, 'target': target});
    }
    _arm(
      ip,
      (a) => (a.boot != null || a.status.isPoweredOn)
          ? a
          : a.copyWith(
              boot: BootInProgress(deadline: _now + timeout, target: target),
            ),
    );
  }

  /// Seeding / debug seam for the dial range, **not persisted**; the
  /// persisted path is `SettingsNotifier.setVolumeLimits`, which this
  /// owner mirrors through its settings listener. Same validity rule, same
  /// limit clamp (3.6.6) — a seeded out-of-range amp is corrected too.
  void setVolumeRange({double? floorDb, double? ceilingDb}) {
    final floor = floorDb ?? state.floorDb;
    final ceiling = ceilingDb ?? state.ceilingDb;
    assert(VolumeLimitRules.validPair(floor, ceiling), 'invalid volume range $floor/$ceiling');
    final changed = floor != state.floorDb || ceiling != state.ceilingDb;
    final view = _viewIfTracing;
    state = state.copyWith(floorDb: floor, ceilingDb: ceiling);
    _afterWrite(view);
    if (changed) _scheduleLimitClamp();
  }

  /// Seeding / debug seam for the step size, **not persisted** (the
  /// persisted path is `SettingsNotifier.setStepDb`, mirrored by the
  /// settings listener); lets a fixture keep its own dial grid.
  void seedStepDb(double stepDb) {
    assert(stepDb > 0, 'step must be positive');
    state = state.copyWith(stepDb: stepDb);
    _afterWrite(null);
  }

  // ---- Intents: synchronous optimistic write → send → rollback on failure

  /// Every optimistic write, rollback and boot-record write passes through
  /// here, so the `view` trace sees each displayed change exactly once.
  void _arm(String ip, TrackedAmp Function(TrackedAmp amp) write) {
    final view = _viewIfTracing;
    state = state.updateAmp(ip, write);
    _afterWrite(view);
  }

  Future<void> _send(
    String ip,
    Future<void> Function(AmpCommandSink sink) send,
    TrackedAmp Function(TrackedAmp amp) rollback,
  ) async {
    try {
      await send(_sink);
    } catch (error) {
      _trace('send failed', {'ip': ip, 'error': error});
      if (ref.mounted) _arm(ip, rollback);
    }
  }

  PendingValue<T> _pending<T>(T value) => PendingValue(value, _now + kPendingWindow);

  static double _quantizeHalfDb(double db) => (db * 2).round() / 2;

  /// The one volume write (Task 3.6.2 / 3.6.5 / 3.6.6): [target] is
  /// already quantized and clamped by the caller through [AmpState.clampDb].
  ///
  /// [userIntent] (VOL ±, the dial) vs a correction (the limit clamp;
  /// the startup send has its own path in [_runBootFollowUps]):
  /// - **Auto-unmute** (3.6.5, a client decision — the wire does not
  ///   unmute): a user change on a muted amp arms `pendingMuted(false)` in
  ///   the same synchronous write and sends `mute off` *before* the volume
  ///   (KDE order). Two separate sends with separate rollbacks, so a
  ///   failed unmute never rolls the volume back. A correction leaves the
  ///   amp muted (3.7.1).
  /// - **Inside a confirmed post-boot hold** (3.6.4b) a user value
  ///   re-targets the deferred startup send (while it has not gone out),
  ///   marks the record `userSent` so a matching broadcast may release the
  ///   hold, and restarts the fallback from this send — the user is never
  ///   overridden by the default (gotcha #9, 4/4 measured) and never left
  ///   waiting on the startup send for confirmation.
  Future<void> _writeVolume(String ip, double target, {required bool userIntent}) async {
    final now = _now;
    var unmute = false;
    _arm(ip, (a) {
      final boot = a.boot;
      final held = userIntent && boot != null && boot.isConfirmed && now < boot.holdDeadline!;
      var next = a.copyWith(pendingVolumeDb: PendingValue(target, now + (held ? kBootHold : kPendingWindow)));
      if (held) {
        next = next.copyWith(boot: boot.copyWith(userSent: true, target: boot.startupSent ? null : target));
      }
      if (userIntent && a.displayedMuted) {
        unmute = true;
        next = next.copyWith(pendingMuted: _pending(false));
      }
      return next;
    });
    if (unmute) await _send(ip, (s) => s.setMute(ip, false), (a) => a.copyWith(pendingMuted: null));
    await _send(ip, (s) => s.setVolumeDb(ip, target), (a) => a.copyWith(pendingVolumeDb: null));
  }

  /// The dial's release value (and any absolute user value): quantized to
  /// the 0.5 dB wire grid and clamped, then written as a user intent.
  Future<void> setVolumeDb(double db) {
    final ip = state.effectiveIp;
    if (ip == null || !_view.commandsAllowed) return Future.value();
    return _writeVolume(ip, state.clampDb(_quantizeHalfDb(db)), userIntent: true);
  }

  /// One discrete input = one step of the configured size (3.6.0), from the
  /// *displayed* value so rapid taps accumulate (5 taps 10 ms apart = 5
  /// steps; checklist 3), clamped through the same function as every other
  /// path (3.6.2). Synchronous; returns whether anything was written, so a
  /// hold-to-repeat chain can stop at a bound without the widget keeping a
  /// copy of the volume (checklist 9). At a bound on a *muted* amp the
  /// press still counts: it unmutes and re-asserts the value (KDE sends
  /// there too); the next tick then reports false.
  bool stepVolume(int direction) {
    final ip = state.effectiveIp;
    final amp = state.selectedAmp;
    if (ip == null || amp == null || !_view.commandsAllowed) return false;
    final base = amp.displayedVolumeDb;
    final target = state.clampDb(_quantizeHalfDb(base + direction * state.stepDb));
    if (target == base && !amp.displayedMuted) return false;
    unawaited(_writeVolume(ip, target, userIntent: true));
    return true;
  }

  Future<void> toggleMute() async {
    final ip = state.effectiveIp;
    final amp = state.selectedAmp;
    if (ip == null || amp == null || !_view.commandsAllowed) return;
    final target = !amp.displayedMuted;
    _arm(ip, (a) => a.copyWith(pendingMuted: _pending(target)));
    await _send(ip, (s) => s.setMute(ip, target), (a) => a.copyWith(pendingMuted: null));
  }

  /// Task 3.2.0. On → Off is immediate and optimistic (and cancels any
  /// boot follow-ups). Off → On enters Booting through [markBooting] with
  /// no optimistic On; the amp's broadcast confirms it, or the 20 s
  /// timeout falls back to Off. Booting → no-op, so repeated taps don't
  /// extend the deadline. An Off that is only optimistic (the amp still
  /// reports On) is simply cancelled: a stale On must not "confirm" a boot.
  Future<void> togglePower() async {
    final ip = state.effectiveIp;
    final amp = state.selectedAmp;
    if (ip == null || amp == null || !_view.powerCommandAllowed) return;
    if (amp.displayedPower) {
      _arm(ip, (a) => a.copyWith(pendingPower: _pending(false), boot: null));
      await _send(ip, (s) => s.setPower(ip, false), (a) => a.copyWith(pendingPower: null));
    } else if (amp.status.isPoweredOn) {
      _arm(ip, (a) => a.copyWith(pendingPower: null));
      await _send(ip, (s) => s.setPower(ip, true), (a) => a);
    } else {
      markBooting(ip);
      await _send(ip, (s) => s.setPower(ip, true), (a) => a.copyWith(boot: null));
    }
  }

  Future<void> selectSource(int statusIndex) async {
    final ip = state.effectiveIp;
    if (ip == null || !_view.commandsAllowed) return;
    if (!_view.sources.any((s) => s.index == statusIndex)) return;
    _arm(ip, (a) => a.copyWith(pendingSource: _pending(statusIndex)));
    await _send(ip, (s) => s.selectSource(ip, statusIndex), (a) => a.copyWith(pendingSource: null));
  }
}

final ampStateProvider = NotifierProvider<AmpStateOwner, AmpState>(AmpStateOwner.new);

/// What every surface renders. Same name as the Task 2.0.x fake so the UI's
/// `ref.watch` sites are untouched; [ControlViewState.==] suppresses
/// rebuilds when a broadcast changes nothing visible.
final controlViewStateProvider = Provider<ControlViewState>((ref) => deriveControlView(ref.watch(ampStateProvider)));

/// The unmasked confirmed channel for Task 3.10.x feedback.
final confirmedAmpStateProvider = Provider<ConfirmedAmpState?>((ref) => deriveConfirmed(ref.watch(ampStateProvider)));
