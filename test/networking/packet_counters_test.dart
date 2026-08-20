import 'package:devialet_expert_remote_app/networking/packet_counters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PacketCounters', () {
    test('starts both counters at 0', () {
      final counters = PacketCounters();
      final first = counters.next();
      expect(first.packetCounter, 0);
      expect(first.commandCounter, 0);
    });

    test('advances BOTH counters on every call, not once per logical command', () {
      // docs/protocol.md "Counter caveat": buildCommand() advances both
      // counters on every call, and sendTwice() calls it twice per logical
      // command — so two calls here must NOT produce identical pairs.
      final counters = PacketCounters();
      final first = counters.next();
      final second = counters.next();
      expect(second.packetCounter, first.packetCounter + 1);
      expect(second.commandCounter, first.commandCounter + 1);
    });

    test('wraps 0xFFFF -> 0 for both counters', () {
      final counters = PacketCounters();
      // Advance to 0xFFFF.
      for (var i = 0; i < 0xFFFF; i++) {
        counters.next();
      }
      final last = counters.next();
      expect(last.packetCounter, 0xFFFF);
      expect(last.commandCounter, 0xFFFF);

      final wrapped = counters.next();
      expect(wrapped.packetCounter, 0);
      expect(wrapped.commandCounter, 0);
    });
  });
}
