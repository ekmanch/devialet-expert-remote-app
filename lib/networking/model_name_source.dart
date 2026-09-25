/// The seam between the owner's model-name resolver (`lib/domain/`) and
/// whatever finds `_spotify-connect._tcp` services on this platform (Task
/// 3.9.5): pure-Dart `multicast_dns` on Android and desktop, native
/// Bonjour on iOS (`lib/platform/`). Strings only — no `dart:io` type
/// crosses this seam, like `UdpDatagram.senderAddress`.
library;

/// One resolved service instance: the SRV target / host name exactly as
/// announced (`Expert140Pro-K48A00904ZE1V.local`, with or without a
/// trailing dot) and its first IPv4 address as a dotted quad.
typedef ModelNameHit = ({String hostname, String ip});

/// Where `(hostname, ip)` pairs come from.
///
/// Subscribing to [browse] starts a browse session; cancelling stops it.
/// Duplicate hits are allowed (the resolver dedupes). A stream **error**
/// means the source cannot run at all — the 5353 bind or a multicast join
/// failed, a permission is missing — and is terminal: the stream closes
/// after it. A source that simply hears nothing stays open and silent.
abstract interface class ModelNameSource {
  Stream<ModelNameHit> browse();
}

/// Hears nothing, never errors: the provider's default until `main.dart`
/// installs the platform source, and what a hermetic test gets.
class NoopModelNameSource implements ModelNameSource {
  const NoopModelNameSource();

  @override
  Stream<ModelNameHit> browse() => const Stream.empty();
}

/// Held for the duration of a browse session. Android filters multicast
/// off the Wi-Fi radio unless an app holds `WifiManager.MulticastLock`
/// (a no-op elsewhere); the `MethodChannel` implementation lives in
/// `lib/platform/android_multicast_lock.dart`.
abstract interface class MulticastLock {
  Future<void> acquire();
  Future<void> release();
}

class NoopMulticastLock implements MulticastLock {
  const NoopMulticastLock();

  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}
