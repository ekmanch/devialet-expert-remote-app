/// Tracks the two uint16 counters written into every command packet.
///
/// Per `docs/protocol.md` ("Counter caveat"), the original app's
/// `sendTwice()` calls `buildCommand()` twice per logical command, and
/// `buildCommand()` advances *both* counters on every call — so a single
/// logical action (e.g. one mute toggle) consumes two packet-counter values
/// and two command-counter values, not one shared pair. This is preserved
/// here deliberately, not "cleaned up", since whether the amp requires
/// counter continuity is unconfirmed (see protocol.md's open questions).
///
/// Starting value (0 for both counters) is an assumption — protocol.md does
/// not document what the amp expects the very first counter value to be.
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
