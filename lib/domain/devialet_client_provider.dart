import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../networking/devialet_client.dart';
import '../networking/udp_transport.dart';

/// Thin Riverpod wiring around the networking layer for this phase — just
/// enough to let UI (currently only the debug screen) trigger commands and
/// observe status. Deliberately does NOT yet include discovery, staleness
/// tracking, or the volume debounce windows from `docs/known-gotchas.md`
/// #1-#2; those belong to the domain/state phase later in the port plan.
final devialetTransportProvider = Provider<UdpTransport>((ref) {
  final transport = DevialetUdpTransport();
  ref.onDispose(transport.close);
  return transport;
});

final devialetClientProvider = Provider<DevialetClient>((ref) {
  final client = DevialetClient(transport: ref.watch(devialetTransportProvider));
  ref.onDispose(client.dispose);
  return client;
});

/// A plain view of the broadcast stream for the debug network screen. The
/// socket's lifetime belongs to the owner (`amp_state_owner.dart`), which
/// starts listening on build and stops on dispose — this provider must
/// not stop it (`stopListening` closes the transport).
final ampStatusStreamProvider = StreamProvider<AmpStatusReport>(
  (ref) => ref.watch(devialetClientProvider).statusReports,
);
