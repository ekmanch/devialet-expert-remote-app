import '../networking/devialet_client.dart' show AmpStatusReport;
import 'amp_tracker.dart';
import 'control_view_state.dart';

const Object _unset = Object();

/// The owner's raw model (port of the KDE daemon's `AmpState`): every amp
/// ever heard, the selection, and the clock reading the model was last
/// brought up to. Pure data; `deriveControlView` turns it into what the
/// UI renders and `deriveConfirmed` into the unmasked feedback channel.
class AmpState {
  const AmpState({
    required this.amps,
    required this.selectedIp,
    required this.hasExplicitSelection,
    required this.now,
    required this.floorDb,
    required this.ceilingDb,
    required this.startupVolumeDb,
    required this.stepDb,
    this.visibleSheet = SheetKind.none,
    this.manualIp,
  });

  /// Defaults mirror `AppSettings.defaults`; the owner overrides them with
  /// the persisted settings on build (Task 3.3.x). The wire ceiling is the
  /// required `maxDb` the sink reads from the same settings at send time
  /// (Task 3.4.7 / 1.1.3).
  static const AmpState initial = AmpState(
    amps: <String, TrackedAmp>{},
    selectedIp: null,
    hasExplicitSelection: false,
    now: Duration.zero,
    floorDb: -50.0,
    ceilingDb: -10.0,
    startupVolumeDb: -40.0,
    stepDb: 1.0,
  );

  /// Keyed by sender IP. **Never evicted**: a silent amp flips offline via
  /// [TrackedAmp.isOnlineAt], it is not forgotten.
  final Map<String, TrackedAmp> amps;

  /// `null` == None. Meaningful only together with [hasExplicitSelection]:
  /// "chose None" and "never chose" are distinct states (checklist 4).
  final String? selectedIp;
  final bool hasExplicitSelection;

  /// Monotonic clock reading at the last ingest/tick.
  final Duration now;

  /// From the persisted settings (`AppSettings`); the floor is UI-only.
  final double floorDb;
  final double ceilingDb;

  /// Sent 500 ms after a self-initiated boot confirms (Task 3.2.2) and,
  /// later, after every source switch (Task 3.8.1). Persisted setting.
  final double startupVolumeDb;

  /// One discrete input (VOL ± tap or repeat tick) moves this much and the
  /// dial snaps to it (Task 3.6.0). Persisted setting (0.5 / 1 / 2).
  final double stepDb;

  /// The one sheet slot (Task 3.8.2 / 3.0.6); see [ControlViewState.visibleSheet].
  /// Transient UI state, deliberately not persisted.
  final SheetKind visibleSheet;

  /// The last IP typed into the manual-entry view in this process (Task
  /// 3.9.3). Only presentation reads it — the sheet's "MANUAL" tag on the
  /// never-heard row — and only while it is the selection and unheard, so
  /// it never needs clearing: hearing the IP or choosing another amp
  /// retires the tag by itself. Never persisted (see [AmpRef.manual]).
  final String? manualIp;

  /// Task 3.6.2: the one clamp every volume write passes through
  /// (min/max, idempotent — `clamp(clamp(x)) == clamp(x)`).
  double clampDb(double db) => db.clamp(floorDb, ceilingDb);

  bool inRange(double db) => db >= floorDb && db <= ceilingDb;

  /// The amp whose broadcasts drive the control state: the explicit
  /// selection, or — only if the user never chose — the sole known amp
  /// (auto-select-if-alone). With 0 or 2+ amps and no choice, nothing.
  String? get effectiveIp {
    if (hasExplicitSelection) return selectedIp;
    return amps.length == 1 ? amps.keys.single : null;
  }

  TrackedAmp? get selectedAmp {
    final ip = effectiveIp;
    return ip == null ? null : amps[ip];
  }

  bool get selectedOnline => selectedAmp?.isOnlineAt(now) ?? false;

  /// The post-boot volume, clamped to the limits in force (the setting
  /// itself is never rewritten by a limit change).
  double get startupVolumeTarget => startupVolumeDb.clamp(floorDb, ceilingDb);

  /// Every broadcast feeds the map; pending slots, boot deadline and model
  /// name are carried forward (a broadcast must not wipe an armed mask),
  /// then resolved against the new report.
  AmpState ingest(AmpStatusReport report, Duration now) {
    final previous = amps[report.senderIp];
    var boot = previous?.boot;
    // Task 3.2.5 (owner decision 2026-09-20, reversing 3.2.2's "not on an
    // external power-on"): an Off→On observed on the *selected* amp that
    // this app did not initiate (the KDE widget, the remote, the front
    // panel) gets the same post-boot follow-ups. The record is created
    // here, due for confirmation by this very packet, so `resolvePending`
    // arms the hold and the owner sends the startup volume at +500 ms —
    // the only thing that re-syncs the amp's misreporting broadcast
    // (gotcha #8). Consequence: the app then sets its startup volume after
    // a front-panel boot too, overriding one configured in the amp itself.
    final externalPowerOn = boot == null &&
        previous != null &&
        !previous.status.isPoweredOn &&
        report.status.isPoweredOn &&
        report.senderIp == effectiveIp;
    if (externalPowerOn) boot = BootInProgress(deadline: now, target: startupVolumeTarget);
    final next = TrackedAmp(
      ip: report.senderIp,
      status: report.status,
      lastSeen: now,
      modelName: previous?.modelName,
      boot: boot,
      pendingVolumeDb: previous?.pendingVolumeDb,
      pendingMuted: previous?.pendingMuted,
      pendingPower: previous?.pendingPower,
      pendingSource: previous?.pendingSource,
    ).resolvePending(now);
    return copyWith(amps: {...amps, report.senderIp: next}, now: now);
  }

  /// The 1 s tick: expire deadlines with no broadcast in between.
  AmpState tick(Duration now) => copyWith(
    amps: {for (final e in amps.entries) e.key: e.value.resolvePending(now)},
    now: now,
  );

  AmpState updateAmp(String ip, TrackedAmp Function(TrackedAmp amp) update) {
    final amp = amps[ip];
    if (amp == null) return this;
    return copyWith(amps: {...amps, ip: update(amp)});
  }

  AmpState copyWith({
    Map<String, TrackedAmp>? amps,
    Object? selectedIp = _unset,
    bool? hasExplicitSelection,
    Duration? now,
    double? floorDb,
    double? ceilingDb,
    double? startupVolumeDb,
    double? stepDb,
    SheetKind? visibleSheet,
    String? manualIp,
  }) {
    return AmpState(
      amps: amps ?? this.amps,
      selectedIp: identical(selectedIp, _unset) ? this.selectedIp : selectedIp as String?,
      hasExplicitSelection: hasExplicitSelection ?? this.hasExplicitSelection,
      now: now ?? this.now,
      floorDb: floorDb ?? this.floorDb,
      ceilingDb: ceilingDb ?? this.ceilingDb,
      startupVolumeDb: startupVolumeDb ?? this.startupVolumeDb,
      stepDb: stepDb ?? this.stepDb,
      visibleSheet: visibleSheet ?? this.visibleSheet,
      manualIp: manualIp ?? this.manualIp,
    );
  }
}

/// What the amp itself last reported for the selected amp — never through
/// a pending slot. Feedback (Task 3.10.x) derives from this, not from the
/// gesture (checklist 25). [receivedAt] makes every broadcast a distinct
/// value so listeners see each confirmation.
class ConfirmedAmpState {
  const ConfirmedAmpState({
    required this.ip,
    required this.volumeRaw,
    required this.volumeDb,
    required this.isMuted,
    required this.isPoweredOn,
    required this.activeSourceIndex,
    required this.receivedAt,
  });

  final String ip;
  final int volumeRaw;
  final double volumeDb;
  final bool isMuted;
  final bool isPoweredOn;
  final int activeSourceIndex;
  final Duration receivedAt;

  @override
  bool operator ==(Object other) =>
      other is ConfirmedAmpState &&
      other.ip == ip &&
      other.volumeRaw == volumeRaw &&
      other.isMuted == isMuted &&
      other.isPoweredOn == isPoweredOn &&
      other.activeSourceIndex == activeSourceIndex &&
      other.receivedAt == receivedAt;

  @override
  int get hashCode => Object.hash(ip, volumeRaw, isMuted, isPoweredOn, activeSourceIndex, receivedAt);
}

ConfirmedAmpState? deriveConfirmed(AmpState s) {
  final amp = s.selectedAmp;
  if (amp == null || !amp.isOnlineAt(s.now)) return null;
  return ConfirmedAmpState(
    ip: amp.ip,
    volumeRaw: amp.status.volumeRaw,
    volumeDb: amp.status.volumeDb,
    isMuted: amp.status.isMuted,
    isPoweredOn: amp.status.isPoweredOn,
    activeSourceIndex: amp.status.activeSourceIndex,
    receivedAt: amp.lastSeen,
  );
}

/// The one derivation from the raw model to what every surface renders
/// (KDE `recompute()`). Pure: same model, same view.
///
/// Every amp ever heard is listed (the map never evicts), online ones
/// first, then the silent ones, each group in numeric IP order (Task
/// 3.9.0, the owner's v44 mockups). A selection that is not reachable —
/// silent for 8 s, or never heard — yields the **waiting** shape: the
/// selection stays named, nothing is controllable, and there is no
/// reading (`volumeDb == null`, Task 3.9.4). The persisted selection is
/// untouched so the next broadcast reconnects without a tap (3.0.8).
ControlViewState deriveControlView(AmpState s) {
  final online = <AmpRef>[];
  final offline = <AmpRef>[];
  for (final amp in s.amps.values) {
    final isOnline = amp.isOnlineAt(s.now);
    (isOnline ? online : offline).add(
      AmpRef(
        id: amp.ip,
        name: amp.status.deviceName,
        model: amp.modelName,
        ip: amp.ip,
        online: isOnline,
        silentFor: isOnline ? null : silentForBucket(s.now - amp.lastSeen),
      ),
    );
  }
  online.sort((a, b) => _compareIps(a.ip, b.ip));
  offline.sort((a, b) => _compareIps(a.ip, b.ip));

  final ip = s.effectiveIp;
  final amp = s.selectedAmp;
  if (ip != null && amp == null) {
    // Selected but never heard (a typed IP, or a restored selection before
    // its first packet): one synthetic row, last, so the sheet can show
    // and check it.
    offline.add(AmpRef(id: ip, name: '', ip: ip, online: false, heard: false, manual: s.manualIp == ip));
  }
  final knownAmps = [...online, ...offline];

  if (ip == null) {
    return ControlViewState(
      connection: ConnectionPhase.notConnected,
      selectedAmp: null,
      selectedIp: s.selectedIp,
      knownAmps: knownAmps,
      power: PowerPhase.off,
      isMuted: false,
      volumeDb: null,
      floorDb: s.floorDb,
      ceilingDb: s.ceilingDb,
      stepDb: s.stepDb,
      sources: const <SourceItem>[],
      activeSourceIndex: null,
      visibleSheet: s.visibleSheet,
    );
  }

  if (amp == null || !amp.isOnlineAt(s.now)) {
    return ControlViewState(
      connection: ConnectionPhase.waiting,
      selectedAmp: knownAmps.firstWhere((a) => a.ip == ip),
      selectedIp: s.selectedIp,
      knownAmps: knownAmps,
      power: PowerPhase.off,
      isMuted: false,
      volumeDb: null,
      floorDb: s.floorDb,
      ceilingDb: s.ceilingDb,
      stepDb: s.stepDb,
      sources: const <SourceItem>[],
      activeSourceIndex: null,
      visibleSheet: s.visibleSheet,
    );
  }

  return ControlViewState(
    connection: ConnectionPhase.connected,
    selectedAmp: knownAmps.firstWhere((a) => a.ip == ip),
    selectedIp: s.selectedIp,
    knownAmps: knownAmps,
    power: amp.powerPhaseAt(s.now),
    isMuted: amp.displayedMuted,
    volumeDb: amp.displayedVolumeDb,
    floorDb: s.floorDb,
    ceilingDb: s.ceilingDb,
    stepDb: s.stepDb,
    sources: [
      for (final slot in amp.status.sources)
        if (slot.isEnabled) SourceItem(index: slot.index, name: slot.name),
    ],
    activeSourceIndex: amp.displayedSourceIndex,
    visibleSheet: s.visibleSheet,
  );
}

/// Quantizes a silence to the granularity the sheet prints — "just now"
/// under a minute, whole minutes under an hour, whole hours beyond — so a
/// silent amp's row only changes the view when its label would change
/// (`ControlViewState` equality suppresses rebuilds, architecture §3).
Duration silentForBucket(Duration silent) {
  if (silent < const Duration(minutes: 1)) return Duration.zero;
  if (silent < const Duration(hours: 1)) return Duration(minutes: silent.inMinutes);
  return Duration(hours: silent.inHours);
}

/// Numeric IPv4 order so the list only reorders when the IP set changes,
/// never because an entry's name or online state flipped (KDE).
int _compareIps(String a, String b) {
  final pa = a.split('.').map(int.tryParse).toList();
  final pb = b.split('.').map(int.tryParse).toList();
  if (pa.length == 4 && pb.length == 4 && !pa.contains(null) && !pb.contains(null)) {
    for (var i = 0; i < 4; i++) {
      final c = pa[i]!.compareTo(pb[i]!);
      if (c != 0) return c;
    }
    return 0;
  }
  return a.compareTo(b);
}
