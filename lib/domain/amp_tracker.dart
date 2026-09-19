import '../networking/status_packet.dart';
import 'control_view_state.dart' show PowerPhase;

/// Pending-command window: after a local write the local value is
/// authoritative until a broadcast matches it exactly or this elapses.
/// Same 400 ms as the Kotlin app, the earlier Flutter debounce and the KDE
/// daemon (`docs/protocol.md`, "Timing facts").
const Duration kPendingWindow = Duration(milliseconds: 400);

/// An amp not heard from for this long is offline (`online = last_seen < 8 s`).
const Duration kStaleAfter = Duration(seconds: 8);

/// Boot timeout — real boots measured 15.0–18.6 s; 15 s flashed "Off" first
/// (`docs/protocol.md`, "Timing facts").
const Duration kBootTimeout = Duration(seconds: 20);

/// Gotcha #9: a volume command sent before the amp has applied its own
/// startup volume is dropped. Latest observed amp-side application was
/// +394 ms after the first On packet; 500 ms is the smallest round value
/// above it. Deadlines are evaluated on ingest (5 Hz) and the 1 s tick, so
/// the effective delay is +500…+700 ms — never earlier.
const Duration kStartupVolumeDelay = Duration(milliseconds: 500);

/// Gotcha #8 / Task 3.2.3: how long the shown volume is held at the boot
/// target while the amp misreports (−42.0) — released earlier by a
/// confirming broadcast equal to the target.
const Duration kBootHold = Duration(milliseconds: 1500);

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

/// A self-initiated power-on in progress (Task 3.2.x). Its existence *is*
/// the "self-initiated" flag: only `AmpStateOwner.togglePower` creates
/// one, so an On broadcast with no record (front panel, remote, late On
/// after the timeout) gets neither the startup-volume send nor the display
/// hold — that path stays exposed to gotcha #8 by decision.
class BootInProgress {
  const BootInProgress({
    required this.deadline,
    required this.target,
    this.confirmedAt,
    this.startupSent = false,
  });

  /// Unconfirmed past this → silently Off (20 s).
  final Duration deadline;

  /// The startup volume to send and hold. Clamped at creation; a user
  /// change inside the hold re-targets it (gotcha #9: the amp honours a
  /// user value in the window, so the deferred send must not override it).
  final double target;

  /// Set by [TrackedAmp.resolvePending] on the first On broadcast.
  final Duration? confirmedAt;

  /// Flipped by the owner *before* it awaits the send, so a second ingest
  /// during the await cannot send twice.
  final bool startupSent;

  bool get isConfirmed => confirmedAt != null;
  Duration? get sendAt => confirmedAt == null ? null : confirmedAt! + kStartupVolumeDelay;
  Duration? get holdDeadline => confirmedAt == null ? null : confirmedAt! + kBootHold;

  BootInProgress copyWith({Duration? confirmedAt, double? target, bool? startupSent}) => BootInProgress(
    deadline: deadline,
    target: target ?? this.target,
    confirmedAt: confirmedAt ?? this.confirmedAt,
    startupSent: startupSent ?? this.startupSent,
  );

  @override
  bool operator ==(Object other) =>
      other is BootInProgress &&
      other.deadline == deadline &&
      other.target == target &&
      other.confirmedAt == confirmedAt &&
      other.startupSent == startupSent;

  @override
  int get hashCode => Object.hash(deadline, target, confirmedAt, startupSent);
}

/// Everything the owner knows about one amp, keyed by its IP in
/// `AmpState.amps` (port of the KDE daemon's `TrackedAmp`). Immutable;
/// the owner replaces entries.
class TrackedAmp {
  const TrackedAmp({
    required this.ip,
    required this.status,
    required this.lastSeen,
    this.modelName,
    this.boot,
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

  /// Non-null from a self-initiated power-on until its follow-ups are done.
  final BootInProgress? boot;

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
    final b = boot;
    if (b != null && !b.isConfirmed && now < b.deadline) return PowerPhase.booting;
    return displayedPower ? PowerPhase.on : PowerPhase.off;
  }

  /// Clears every pending slot the amp has confirmed exactly or whose
  /// deadline has passed, and advances the boot record. Run on every
  /// ingest and on the 1 s tick.
  ///
  /// Boot rules (Task 3.2.x):
  /// - unconfirmed and the amp reports On → `confirmedAt = now` and the
  ///   **display hold is armed as the pending mask**:
  ///   `pendingVolumeDb = (target, now + kBootHold)`. Release on an exact
  ///   match or at the deadline is precisely the hold rule; the post-boot
  ///   misreport lands in [status] (the confirmed channel) but is not
  ///   displayed. Armed in the same resolve as the confirming packet, so
  ///   that packet's pre-shutdown byte is never shown.
  /// - unconfirmed past [BootInProgress.deadline] → dropped (silent Off).
  /// - confirmed, startup sent and the hold deadline passed → dropped.
  TrackedAmp resolvePending(Duration now) {
    PendingValue<T>? keep<T>(PendingValue<T>? pending, T actual) {
      if (pending == null) return null;
      if (pending.isConfirmedBy(actual) || pending.isExpiredAt(now)) return null;
      return pending;
    }

    var nextBoot = boot;
    var nextPendingVolume = pendingVolumeDb;
    final b = boot;
    if (b != null) {
      if (!b.isConfirmed) {
        if (status.isPoweredOn) {
          nextBoot = b.copyWith(confirmedAt: now);
          nextPendingVolume = PendingValue(b.target, now + kBootHold);
        } else if (now >= b.deadline) {
          nextBoot = null;
        }
      } else if (b.startupSent && now >= b.holdDeadline!) {
        nextBoot = null;
      }
    }

    return copyWith(
      boot: nextBoot,
      pendingVolumeDb: keep(nextPendingVolume, status.volumeDb),
      pendingMuted: keep(pendingMuted, status.isMuted),
      pendingPower: keep(pendingPower, status.isPoweredOn),
      pendingSource: keep(pendingSource, status.activeSourceIndex),
    );
  }

  TrackedAmp copyWith({
    DevialetStatus? status,
    Duration? lastSeen,
    Object? modelName = _unset,
    Object? boot = _unset,
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
      boot: identical(boot, _unset) ? this.boot : boot as BootInProgress?,
      pendingVolumeDb: identical(pendingVolumeDb, _unset)
          ? this.pendingVolumeDb
          : pendingVolumeDb as PendingValue<double>?,
      pendingMuted: identical(pendingMuted, _unset) ? this.pendingMuted : pendingMuted as PendingValue<bool>?,
      pendingPower: identical(pendingPower, _unset) ? this.pendingPower : pendingPower as PendingValue<bool>?,
      pendingSource: identical(pendingSource, _unset) ? this.pendingSource : pendingSource as PendingValue<int>?,
    );
  }
}
