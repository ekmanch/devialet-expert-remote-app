import '../networking/devialet_client.dart' show AmpStatusReport;
import '../networking/volume_codec.dart';
import 'amp_tracker.dart';
import 'control_view_state.dart';

/// Dial range until Task 3.4.x's settings object replaces them.
const double kDefaultFloorDb = -50.0;
const double kDefaultCeilingDb = VolumeCodec.defaultSafetyMaxDb;

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
  });

  static const AmpState initial = AmpState(
    amps: <String, TrackedAmp>{},
    selectedIp: null,
    hasExplicitSelection: false,
    now: Duration.zero,
    floorDb: kDefaultFloorDb,
    ceilingDb: kDefaultCeilingDb,
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
  final double floorDb;
  final double ceilingDb;

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

  /// Every broadcast feeds the map; pending slots, boot deadline and model
  /// name are carried forward (a broadcast must not wipe an armed mask),
  /// then resolved against the new report.
  AmpState ingest(AmpStatusReport report, Duration now) {
    final previous = amps[report.senderIp];
    final next = TrackedAmp(
      ip: report.senderIp,
      status: report.status,
      lastSeen: now,
      modelName: previous?.modelName,
      bootDeadline: previous?.bootDeadline,
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
  }) {
    return AmpState(
      amps: amps ?? this.amps,
      selectedIp: identical(selectedIp, _unset) ? this.selectedIp : selectedIp as String?,
      hasExplicitSelection: hasExplicitSelection ?? this.hasExplicitSelection,
      now: now ?? this.now,
      floorDb: floorDb ?? this.floorDb,
      ceilingDb: ceilingDb ?? this.ceilingDb,
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
/// Silent-amp rule (owner decision 2026-09-19, TODO 3.0.8): an amp not
/// heard for 8 s is presented exactly like no amplifier — hidden from the
/// list, `selectedAmp == null` — while [AmpState.selectedIp] is kept so the
/// next broadcast reconnects without a tap. The view carries
/// [ControlViewState.selectedIp] so Task 3.9.x can show an offline row.
ControlViewState deriveControlView(AmpState s) {
  final knownAmps = [
    for (final amp in s.amps.values)
      if (amp.isOnlineAt(s.now))
        AmpRef(id: amp.ip, name: amp.status.deviceName, model: amp.modelName, ip: amp.ip),
  ]..sort((a, b) => _compareIps(a.ip, b.ip));

  final amp = s.selectedAmp;
  if (amp == null || !amp.isOnlineAt(s.now)) {
    return ControlViewState(
      connection: ConnectionPhase.notConnected,
      selectedAmp: null,
      selectedIp: s.selectedIp,
      knownAmps: knownAmps,
      power: PowerPhase.off,
      isMuted: false,
      // Sentinel: the UI checks `hasAmp` before formatting a reading
      // (checklist 5). Never surfaces as a number.
      volumeDb: s.floorDb,
      floorDb: s.floorDb,
      ceilingDb: s.ceilingDb,
      sources: const <SourceItem>[],
      activeSourceIndex: null,
    );
  }

  return ControlViewState(
    connection: ConnectionPhase.connected,
    selectedAmp: AmpRef(id: amp.ip, name: amp.status.deviceName, model: amp.modelName, ip: amp.ip),
    selectedIp: s.selectedIp,
    knownAmps: knownAmps,
    power: amp.powerPhaseAt(s.now),
    isMuted: amp.displayedMuted,
    volumeDb: amp.displayedVolumeDb,
    floorDb: s.floorDb,
    ceilingDb: s.ceilingDb,
    sources: [
      for (final slot in amp.status.sources)
        if (slot.isEnabled) SourceItem(index: slot.index, name: slot.name),
    ],
    activeSourceIndex: amp.displayedSourceIndex,
  );
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
