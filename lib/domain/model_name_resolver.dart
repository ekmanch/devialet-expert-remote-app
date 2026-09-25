import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../networking/model_name.dart';
import '../networking/model_name_source.dart';
import 'amp_trace.dart';
import 'monotonic_clock.dart';

/// The longest a browse session may run without resolving what it was
/// opened for — a typed IP that is not a Devialet, an amp whose mDNS never
/// answers — so the multicast lock and the query cycle are always bounded.
/// **A guess until measured** (checklist 14).
const Duration kMdnsSessionBudget = Duration(seconds: 60);

/// Task 3.9.5: turns [ModelNameSource] hits into `setModelName` calls on
/// the owner (`docs/protocol.md`, "mDNS model-name resolution"; KDE
/// `resolve_model_name`). Owned by `AmpStateOwner` like its sink and
/// trace; a plain class, not a provider, so there is no owner ↔ resolver
/// cycle.
///
/// Rules:
/// - **Trust gate.** `_spotify-connect._tcp` is not Devialet-specific, so
///   a hit is applied only for an IP the owner has already heard over UDP
///   ([onAmpHeard]); the owner's `setModelName` ignores unknown IPs as
///   well (belt and braces).
/// - **Cache-first replay.** An mDNS answer can land before the first UDP
///   packet from that IP (both arrive within ~1 s of startup), so every
///   hit is cached for the process lifetime and applied the moment its IP
///   becomes known.
/// - **Resolved once.** A settled IP is never re-attempted or cleared.
/// - **Bounded sessions.** [start] opens one session unconditionally (the
///   first query goes out alongside the UDP bind). A session closes once
///   every known IP is settled *and* at least one hit was heard, or at
///   [sessionBudget] regardless; a new unresolved IP with no session open
///   opens a fresh one. The budget is checked on hits and on the owner's
///   1 s tick — no timer of its own (architecture §5).
/// - **Failure is honest** (checklist 26). A source error traces one
///   `mdns unavailable` line and closes the session; the amp keeps its UDP
///   name and the sheet's "· name unresolved" tag says so. A later *new* IP
///   may try once more (bounded by distinct IPs, never per cycle).
class ModelNameResolver {
  ModelNameResolver({
    required this.source,
    required this.apply,
    required this.clock,
    required this.trace,
    this.sessionBudget = kMdnsSessionBudget,
  });

  final ModelNameSource source;

  /// The owner's `setModelName`.
  final void Function(String ip, String model) apply;
  final MonotonicClock clock;
  final AmpTrace trace;
  final Duration sessionBudget;

  /// Every hit ever heard, first hostname per IP wins.
  final Map<String, String> _hostnameByIp = {};

  /// IPs the owner has heard over UDP.
  final Set<String> _known = {};

  /// Known IPs that need no further work: applied, or cached with a
  /// hostname that parses to nothing.
  final Set<String> _settled = {};

  StreamSubscription<ModelNameHit>? _session;
  Duration? _sessionOpenedAt;
  bool _heardInSession = false;
  bool _disposed = false;

  bool get sessionOpen => _session != null;

  /// The known IPs still waiting for a name (read-only, for tests).
  Set<String> get unresolved => _known.difference(_settled);

  void start() => _open('start');

  /// The owner heard [ip] over UDP for the first time.
  void onAmpHeard(String ip) {
    if (_disposed || !_known.add(ip)) return;
    if (_settle(ip)) {
      _maybeClose();
      return;
    }
    if (_session == null) _open('new-ip');
  }

  /// The owner's 1 s tick: enforce the session budget.
  void onTick() {
    final openedAt = _sessionOpenedAt;
    if (_session != null && openedAt != null && clock.now() - openedAt >= sessionBudget) _close('budget');
  }

  void dispose() {
    _disposed = true;
    _close('dispose');
  }

  void _onHit(ModelNameHit hit) {
    _heardInSession = true;
    if (!_hostnameByIp.containsKey(hit.ip)) {
      _hostnameByIp[hit.ip] = hit.hostname;
      trace('mdns hit', {'host': hit.hostname, 'ip': hit.ip, 'known': _known.contains(hit.ip)});
    }
    if (_known.contains(hit.ip)) _settle(hit.ip);
    _maybeClose();
  }

  /// Applies the cached hostname for a known [ip] if there is one. Returns
  /// whether [ip] is settled afterwards.
  bool _settle(String ip) {
    if (_settled.contains(ip)) return true;
    final host = _hostnameByIp[ip];
    if (host == null) return false;
    final model = parseModelName(host);
    if (model != null) {
      apply(ip, model);
      trace('mdns applied', {'ip': ip, 'model': model});
    }
    _settled.add(ip);
    return true;
  }

  void _maybeClose() {
    if (_session != null && _heardInSession && unresolved.isEmpty) _close('resolved');
  }

  void _open(String reason) {
    if (_disposed || _session != null) return;
    trace('mdns session open', {'reason': reason});
    _sessionOpenedAt = clock.now();
    _heardInSession = false;
    _session = source.browse().listen(
      _onHit,
      onError: (Object error) {
        trace('mdns unavailable', {'error': error});
        _close(null);
      },
      onDone: () {
        // The source closed by itself (after an error, or a finite fake).
        _session = null;
      },
    );
  }

  void _close(String? reason) {
    final session = _session;
    if (session == null) return;
    _session = null;
    unawaited(session.cancel());
    if (reason != null) trace('mdns session close', {'reason': reason});
  }
}

/// Hears nothing by default; `main.dart` installs the platform source and
/// every test harness a fake, so nothing binds port 5353 under
/// `flutter test` (checklist 19).
final modelNameSourceProvider = Provider<ModelNameSource>((_) => const NoopModelNameSource());
