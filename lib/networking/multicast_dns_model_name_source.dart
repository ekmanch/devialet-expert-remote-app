import 'dart:async';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'model_name_source.dart';

/// How often a browse session puts a fresh PTR query on the wire while it
/// runs. **A guess until measured on the Galaxy S25** (checklist 14; the
/// KDE widget's continuous browse resolved in < 0.6 s) — the live run in
/// `docs/protocol-verification-*-discovery.md` records the measured
/// value.
const Duration kMdnsQueryInterval = Duration(seconds: 2);

/// How long each lookup in a cycle waits for answers. Same caveat.
const Duration kMdnsLookupWindow = Duration(milliseconds: 1000);

/// `_spotify-connect._tcp` over the pure-Dart `multicast_dns` package
/// (Android, and the desktop harness; iOS uses Bonjour — see
/// `lib/platform/bonjour_model_name_source.dart`).
///
/// The package is **one-shot** by design: `lookup()` answers from its
/// cache without sending when the cache has a live entry, and every
/// incoming packet *replaces* the cached list for a (type, name). A
/// continuous browse therefore cannot be built on one long-lived client
/// (checklist 29: the library's real behaviour beats the brief's "one
/// continuous browse"). Each **cycle** is a fresh client — `start()`,
/// PTR → SRV → A, `stop()` — repeated every [queryInterval] for as long
/// as the subscription lives; the resolver keeps sessions short (they end
/// when every known amp is resolved, or on a budget).
///
/// Failure contract ([ModelNameSource]): a `start()` that throws (5353
/// bind, multicast join, the lock) is terminal — one error, stream
/// closed, lock released. An exception after a successful start is that
/// cycle's alone; the next cycle proceeds.
class MulticastDnsModelNameSource implements ModelNameSource {
  MulticastDnsModelNameSource({
    required this.lock,
    MDnsClient Function()? newClient,
    NetworkInterfacesFactory? interfaces,
    this.queryInterval = kMdnsQueryInterval,
    this.lookupWindow = kMdnsLookupWindow,
  }) : _newClient = newClient ?? MDnsClient.new,
       _interfaces = interfaces ?? ipv4Interfaces;

  /// No trailing dot: the package decodes names without one and matches
  /// its cache on the exact string.
  static const String serviceName = '_spotify-connect._tcp.local';

  final MulticastLock lock;
  final MDnsClient Function() _newClient;
  final NetworkInterfacesFactory _interfaces;
  final Duration queryInterval;
  final Duration lookupWindow;

  /// `MDnsClient.start` joins the multicast group on every interface its
  /// factory returns and aborts on the first failure; a cellular or VPN
  /// interface with no IPv4 address throws on Android. Keep the ones that
  /// can actually carry IPv4 multicast.
  static Future<Iterable<NetworkInterface>> ipv4Interfaces(InternetAddressType type) async {
    final all = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: true);
    return all.where((i) => i.addresses.any((a) => a.type == InternetAddressType.IPv4 && !a.isLoopback));
  }

  @override
  Stream<ModelNameHit> browse() {
    final session = _Session();
    session.controller = StreamController<ModelNameHit>(
      onListen: () => unawaited(_run(session)),
      onCancel: () => _cancel(session),
    );
    return session.controller.stream;
  }

  Future<void> _run(_Session s) async {
    try {
      await lock.acquire();
    } catch (e, st) {
      s.controller.addError(e, st);
      await s.controller.close();
      return;
    }
    try {
      while (!s.cancelled) {
        final began = Stopwatch()..start();
        final client = _newClient();
        s.inFlight = client;
        try {
          s.starting = client.start(interfacesFactory: _interfaces);
          await s.starting;
        } catch (e, st) {
          s.inFlight = null;
          s.controller.addError(e, st);
          break;
        }
        try {
          if (!s.cancelled) await _cycle(client, s);
        } catch (_) {
          // This cycle's alone: a malformed answer, a socket closed under
          // us by cancel. The next cycle starts clean.
        } finally {
          s.inFlight = null;
          client.stop();
        }
        if (s.cancelled) break;
        final remaining = queryInterval - began.elapsed;
        if (remaining > Duration.zero) await s.sleep(remaining);
      }
    } finally {
      await lock.release();
      await s.controller.close();
    }
  }

  Future<void> _cycle(MDnsClient client, _Session s) async {
    final seen = <String>{};
    final ptrs = client.lookup<PtrResourceRecord>(
      ResourceRecordQuery.serverPointer(serviceName),
      timeout: lookupWindow,
    );
    await for (final ptr in ptrs) {
      if (s.cancelled) return;
      if (!seen.add(ptr.domainName)) continue;
      final srv = await _first(
        client.lookup<SrvResourceRecord>(ResourceRecordQuery.service(ptr.domainName), timeout: lookupWindow),
      );
      if (srv == null || s.cancelled) continue;
      final a = await _first(
        client
            .lookup<IPAddressResourceRecord>(ResourceRecordQuery.addressIPv4(srv.target), timeout: lookupWindow)
            .where((r) => r.address.type == InternetAddressType.IPv4),
      );
      if (a == null || s.cancelled) continue;
      s.controller.add((hostname: srv.target, ip: a.address.address));
    }
  }

  static Future<T?> _first<T>(Stream<T> stream) async {
    await for (final item in stream) {
      return item;
    }
    return null;
  }

  Future<void> _cancel(_Session s) async {
    s.cancelled = true;
    s.wake();
    // `stop()` throws while a start is in flight; wait it out first.
    try {
      await s.starting;
    } catch (_) {}
    s.inFlight?.stop();
  }
}

class _Session {
  late StreamController<ModelNameHit> controller;
  bool cancelled = false;
  MDnsClient? inFlight;
  Future<void>? starting;
  Completer<void>? _sleeping;

  /// A cancellable delay: [wake] ends it early.
  Future<void> sleep(Duration d) {
    final c = _sleeping = Completer<void>();
    Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  void wake() {
    final c = _sleeping;
    if (c != null && !c.isCompleted) c.complete();
  }
}
