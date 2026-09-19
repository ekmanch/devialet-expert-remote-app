import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../networking/devialet_client.dart';
import 'amp_command_sink.dart';
import 'amp_state.dart';
import 'amp_tracker.dart';
import 'control_view_state.dart';
import 'devialet_client_provider.dart';
import 'monotonic_clock.dart';

/// The one owner of live amp state (TODO 3.0.0; `docs/architecture.md`).
///
/// Ingests every status broadcast into [AmpState.amps] keyed by sender IP,
/// re-evaluates staleness and pending deadlines on the 1 s tick, holds the
/// selection, and applies every intent as a synchronous optimistic write
/// through the pending mask before (later) sending. Views read the derived
/// [controlViewStateProvider]; nothing keeps a private copy.
class AmpStateOwner extends Notifier<AmpState> {
  late MonotonicClock _clock;
  late AmpCommandSink _sink;

  @override
  AmpState build() {
    _clock = ref.watch(monotonicClockProvider);
    _sink = ref.watch(ampCommandSinkProvider);
    final client = ref.watch(devialetClientProvider);
    client.startListening();
    final reports = client.statusReports.listen(ingest);
    final ticks = ref.watch(staleTickProvider).listen((_) => _onTick());
    ref.onDispose(() {
      reports.cancel();
      ticks.cancel();
      client.stopListening();
    });
    return AmpState.initial.copyWith(now: _clock.now());
  }

  Duration get _now => _clock.now();

  ControlViewState get _view => deriveControlView(state);

  // ---- Inputs

  /// The single entry point for broadcasts: the socket, the debug
  /// simulated amp and test seeding all come through here.
  void ingest(AmpStatusReport report) => state = state.ingest(report, _now);

  void _onTick() => state = state.tick(_now);

  // ---- Selection (checklist 4: "chose None" ≠ "never chose")

  void selectIp(String? ip) => state = state.copyWith(selectedIp: ip, hasExplicitSelection: true);

  void selectAmp(AmpRef? amp) => selectIp(amp?.ip);

  /// A never-heard IP is a valid selection; it shows as not connected
  /// until a broadcast from it arrives (`docs/protocol.md`, "Multi-amp").
  void addManualAmp(String ip) => selectIp(ip);

  // ---- Seams for later tasks

  /// Task 3.9.5 (mDNS). Ignored for an amp never heard from.
  void setModelName(String ip, String? model) =>
      state = state.updateAmp(ip, (a) => a.copyWith(modelName: model));

  /// Task 3.2.0 enters Booting through this on a self-initiated power-on;
  /// a boot already in progress is not extended (repeated taps don't move
  /// the deadline).
  void markBooting(String ip, {Duration timeout = kBootTimeout}) =>
      state = state.updateAmp(ip, (a) => a.bootDeadline != null ? a : a.copyWith(bootDeadline: _now + timeout));

  /// Task 3.4.x settings plug in here.
  void setVolumeRange({double? floorDb, double? ceilingDb}) =>
      state = state.copyWith(floorDb: floorDb, ceilingDb: ceilingDb);

  // ---- Intents: synchronous optimistic write → send → rollback on failure

  void _arm(String ip, TrackedAmp Function(TrackedAmp amp) write) => state = state.updateAmp(ip, write);

  Future<void> _send(
    String ip,
    Future<void> Function(AmpCommandSink sink) send,
    TrackedAmp Function(TrackedAmp amp) rollback,
  ) async {
    try {
      await send(_sink);
    } catch (_) {
      if (ref.mounted) _arm(ip, rollback);
    }
  }

  PendingValue<T> _pending<T>(T value) => PendingValue(value, _now + kPendingWindow);

  static double _quantizeHalfDb(double db) => (db * 2).round() / 2;

  Future<void> setVolumeDb(double db) async {
    final ip = state.effectiveIp;
    if (ip == null || !_view.volumeGroupEnabled) return;
    final target = _quantizeHalfDb(db).clamp(state.floorDb, state.ceilingDb);
    _arm(ip, (a) => a.copyWith(pendingVolumeDb: _pending(target)));
    await _send(ip, (s) => s.setVolumeDb(ip, target), (a) => a.copyWith(pendingVolumeDb: null));
  }

  /// Steps from the *displayed* value, so rapid taps accumulate
  /// (5 taps 10 ms apart = 5 steps; checklist item 3).
  Future<void> stepVolume(int direction, {double stepDb = 1.0}) {
    final amp = state.selectedAmp;
    if (amp == null) return Future.value();
    return setVolumeDb(amp.displayedVolumeDb + direction * stepDb);
  }

  Future<void> toggleMute() async {
    final ip = state.effectiveIp;
    final amp = state.selectedAmp;
    if (ip == null || amp == null || !_view.volumeGroupEnabled) return;
    final target = !amp.displayedMuted;
    _arm(ip, (a) => a.copyWith(pendingMuted: _pending(target)));
    await _send(ip, (s) => s.setMute(ip, target), (a) => a.copyWith(pendingMuted: null));
  }

  /// Plain on/off this session; Task 3.2.0 routes the off→on edge through
  /// [markBooting] instead of an optimistic On.
  Future<void> togglePower() async {
    final ip = state.effectiveIp;
    final amp = state.selectedAmp;
    if (ip == null || amp == null || !_view.powerEnabled) return;
    final target = !amp.displayedPower;
    _arm(ip, (a) => a.copyWith(pendingPower: _pending(target)));
    await _send(ip, (s) => s.setPower(ip, target), (a) => a.copyWith(pendingPower: null));
  }

  Future<void> selectSource(int statusIndex) async {
    final ip = state.effectiveIp;
    if (ip == null || !_view.volumeGroupEnabled) return;
    if (!_view.sources.any((s) => s.index == statusIndex)) return;
    _arm(ip, (a) => a.copyWith(pendingSource: _pending(statusIndex)));
    await _send(ip, (s) => s.selectSource(ip, statusIndex), (a) => a.copyWith(pendingSource: null));
  }
}

final ampStateProvider = NotifierProvider<AmpStateOwner, AmpState>(AmpStateOwner.new);

/// What every surface renders. Same name as the Task 2.0.x fake so the UI's
/// `ref.watch` sites are untouched; [ControlViewState.==] suppresses
/// rebuilds when a broadcast changes nothing visible.
final controlViewStateProvider = Provider<ControlViewState>(
  (ref) => deriveControlView(ref.watch(ampStateProvider)),
);

/// The unmasked confirmed channel for Task 3.10.x feedback.
final confirmedAmpStateProvider = Provider<ConfirmedAmpState?>(
  (ref) => deriveConfirmed(ref.watch(ampStateProvider)),
);
