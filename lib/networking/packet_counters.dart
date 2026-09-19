/// Tracks the two uint16 counters written into every command packet.
///
/// Per `docs/protocol.md` ("Counter caveat"), the original app's
/// `sendTwice()` calls `buildCommand()` twice per logical command, and
/// `buildCommand()` advances *both* counters on every call — so a single
/// logical action (e.g. one mute toggle) consumes two packet-counter values
/// and two command-counter values, not one shared pair. This is preserved
/// for wire fidelity with the original app, not because anything depends
/// on it: the amp ignores both counters entirely (verified on the real amp
/// 2026-09-19 — frozen, arbitrary, decreasing and byte-identical duplicate
/// values were all applied; `docs/protocol-verification-2026-09-19.md`).
///
/// Starting at (0, 0) per process is therefore fine; no persisted counter
/// is needed across app restarts.
class PacketCounters {
  int _packetCounter = 0;
  int _commandCounter = 0;

  /// Returns the counter pair to embed in the next packet, then advances
  /// both counters, wrapping 0xFFFF -> 0.
  ({int packetCounter, int commandCounter}) next() {
    final current = (packetCounter: _packetCounter, commandCounter: _commandCounter);
    _packetCounter = (_packetCounter + 1) & 0xFFFF;
    _commandCounter = (_commandCounter + 1) & 0xFFFF;
    return current;
  }
}
