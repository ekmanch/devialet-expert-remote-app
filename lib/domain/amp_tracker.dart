import '../networking/status_packet.dart';
import 'control_view_state.dart' show PowerPhase;

/// Pending-command window: after a local write the local value is
/// authoritative until a broadcast matches it exactly or this elapses.
/// Same 400 ms as the Kotlin app, the earlier Flutter debounce and the KDE
/// daemon (`docs/protocol.md`, "Timing facts").
const Duration kPendingWindow = Duration(milliseconds: 400);

/// An amp not heard from for this long is offline (`online = last_seen < 8 s`).
const Duration kStaleAfter = Duration(seconds: 8);

/// Boot timeout — real boots measured 15.0–18.6 s; 15 s flashed "Off" first.
/// Used by Task 3.2.x; the seam ([TrackedAmp.bootDeadline]) exists now.
const Duration kBootTimeout = Duration(seconds: 20);

/// An optimistic local value with the deadline after which the amp's own
/// report wins again. Confirmation is *exact equality* — the status decode
/// is exact and local writes are quantized, so no epsilon (checklist 1).
class PendingValue<T> {
  const PendingValue(this.value, this.deadline);

  final T value;
  final Duration deadline;

  bool isConfirmedBy(T actual) => actual == value;
  bool isExpiredAt(Duration now) => now >= deadline;

  @override
  bool operator ==(Object other) =>
      other is PendingValue<T> && other.value == value && other.deadline == deadline;

  @override
  int get hashCode => Object.hash(value, deadline);
}

const Object _unset = Object();

/// Everything the owner knows about one amp, keyed by its IP in
/// `AmpState.amps` (port of the KDE daemon's `TrackedAmp`). Immutable;
/// the owner replaces entries.
class TrackedAmp {
  const TrackedAmp({
    required this.ip,
    required this.status,
    required this.lastSeen,
    this.modelName,
    this.bootDeadline,
    this.pendingVolumeDb,
    this.pendingMuted,
    this.pendingPower,
    this.pendingSource,
  });

  final String ip;

  /// The last broadcast, verbatim — the unmasked *confirmed* channel.
  final DevialetStatus status;
  final Duration lastSeen;

  /// mDNS-resolved make/model (Task 3.9.5); never cleared once set.
  final String? modelName;

  /// Non-null while a self-initiated power-on is in progress (Task 3.2.x).
  final Duration? bootDeadline;

  final PendingValue<double>? pendingVolumeDb;
  final PendingValue<bool>? pendingMuted;
  final PendingValue<bool>? pendingPower;
  final PendingValue<int>? pendingSource;

  bool isOnlineAt(Duration now) => now - lastSeen < kStaleAfter;

  // ---- Displayed (masked) values: the pending value while armed, else the
  // amp's report. Applied here, once, for every field (checklist 1, 2).

  double get displayedVolumeDb => pendingVolumeDb?.value ?? status.volumeDb;
  bool get displayedMuted => pendingMuted?.value ?? status.isMuted;
  bool get displayedPower => pendingPower?.value ?? status.isPoweredOn;
  int get displayedSourceIndex => pendingSource?.value ?? status.activeSourceIndex;

  PowerPhase powerPhaseAt(Duration now) {
    final deadline = bootDeadline;
    if (deadline != null && now < deadline) return PowerPhase.booting;
    return displayedPower ? PowerPhase.on : PowerPhase.off;
  }

  /// Clears every pending slot the amp has confirmed exactly or whose
  /// deadline has passed, and the boot deadline once the amp reports On
  /// (a late confirmation still corrects to On) or the timeout elapsed.
  /// Run on every ingest and on the 1 s tick.
  TrackedAmp resolvePending(Duration now) {
    PendingValue<T>? keep<T>(PendingValue<T>? pending, T actual) {
      if (pending == null) return null;
      if (pending.isConfirmedBy(actual) || pending.isExpiredAt(now)) return null;
      return pending;
    }

    final boot = bootDeadline;
    final keepBoot = boot != null && !status.isPoweredOn && now < boot;
    return copyWith(
      bootDeadline: keepBoot ? boot : null,
      pendingVolumeDb: keep(pendingVolumeDb, status.volumeDb),
      pendingMuted: keep(pendingMuted, status.isMuted),
      pendingPower: keep(pendingPower, status.isPoweredOn),
      pendingSource: keep(pendingSource, status.activeSourceIndex),
    );
  }

  TrackedAmp copyWith({
    DevialetStatus? status,
    Duration? lastSeen,
    Object? modelName = _unset,
    Object? bootDeadline = _unset,
    Object? pendingVolumeDb = _unset,
    Object? pendingMuted = _unset,
    Object? pendingPower = _unset,
    Object? pendingSource = _unset,
  }) {
    return TrackedAmp(
      ip: ip,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      modelName: identical(modelName, _unset) ? this.modelName : modelName as String?,
      bootDeadline: identical(bootDeadline, _unset) ? this.bootDeadline : bootDeadline as Duration?,
      pendingVolumeDb: identical(pendingVolumeDb, _unset)
          ? this.pendingVolumeDb
          : pendingVolumeDb as PendingValue<double>?,
      pendingMuted: identical(pendingMuted, _unset) ? this.pendingMuted : pendingMuted as PendingValue<bool>?,
      pendingPower: identical(pendingPower, _unset) ? this.pendingPower : pendingPower as PendingValue<bool>?,
      pendingSource: identical(pendingSource, _unset) ? this.pendingSource : pendingSource as PendingValue<int>?,
    );
  }
}
