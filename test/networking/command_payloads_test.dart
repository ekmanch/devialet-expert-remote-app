import 'package:devialet_expert_remote_app/networking/command_payloads.dart';
import 'package:devialet_expert_remote_app/networking/source_mapping.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandPayloads — command table byte values from docs/protocol.md', () {
    test('Power on = byte6 0x01, byte7 0x01, payload 0x00 0x00', () {
      expect(CommandPayloads.powerOn.byte6, 0x01);
      expect(CommandPayloads.powerOn.byte7, 0x01);
      expect(CommandPayloads.powerOn.byte8, 0x00);
      expect(CommandPayloads.powerOn.byte9, 0x00);
    });

    test('Power off = byte6 0x00, byte7 0x01', () {
      expect(CommandPayloads.powerOff.byte6, 0x00);
      expect(CommandPayloads.powerOff.byte7, 0x01);
    });

    test('Mute on = byte6 0x01, byte7 0x07', () {
      expect(CommandPayloads.muteOn.byte6, 0x01);
      expect(CommandPayloads.muteOn.byte7, 0x07);
    });

    test('Mute off = byte6 0x00, byte7 0x07', () {
      expect(CommandPayloads.muteOff.byte6, 0x00);
      expect(CommandPayloads.muteOff.byte7, 0x07);
    });

    test('Set volume = byte6 0x00, byte7 0x04', () {
      final payload = CommandPayloads.setVolume(-20.0, maxDb: 0.0);
      expect(payload.byte6, 0x00);
      expect(payload.byte7, 0x04);
    });

    test('Select source status index 1 (hardcoded case) = byte6 0x00, byte7 0x05, payload 0x3F 0x80', () {
      final payload = CommandPayloads.selectSource(1);
      expect(payload.byte6, 0x00);
      expect(payload.byte7, 0x05);
      expect(payload.byte8, 0x3F);
      expect(payload.byte9, 0x80);
    });

    test('Select source (other inputs) = byte6 0x00, byte7 0x05', () {
      final payload = CommandPayloads.selectSource(4);
      expect(payload.byte6, 0x00);
      expect(payload.byte7, 0x05);
    });

    test('golden vectors: select-source wire bytes 8-9 for every documented status index', () {
      // Literal (byte8, byte9) pairs from the docs/protocol.md source table,
      // end-to-end through selectSource, so a regression in the mapping
      // table AND the packing formula can't cancel out (the formula tests
      // below re-derive their expectation from the same formula).
      const cases = <(int statusIndex, int byte8, int byte9)>[
        (0, 0xFF, 0xE0), // cmdValue -1, signed packing
        (1, 0x3F, 0x80), // hardcoded special case
        (2, 0x40, 0x00),
        (3, 0x40, 0x60),
        (4, 0x40, 0x80),
        (5, 0x40, 0xA0),
        (14, 0x41, 0x60), // > 7 branch
      ];
      for (final (statusIndex, byte8, byte9) in cases) {
        final payload = CommandPayloads.selectSource(statusIndex);
        expect(payload.byte6, 0x00, reason: 'index $statusIndex byte6');
        expect(payload.byte7, 0x05, reason: 'index $statusIndex byte7');
        expect(payload.byte8, byte8, reason: 'index $statusIndex byte8');
        expect(payload.byte9, byte9, reason: 'index $statusIndex byte9');
      }
    });

    test('raw-fallback index 9 -> 41 10 (float32 9.0; on the owner\'s unit slot 9 aliases to 14, verified 2026-09-19)', () {
      final payload = CommandPayloads.selectSource(9);
      expect((payload.byte8, payload.byte9), (0x41, 0x10));
    });
  });

  group('SourceMapping — pinned bytes, else bfloat16(index) (Task 1.1.4, 2026-09-24)', () {
    /// The retired formula, inlined so the test does not depend on it
    /// surviving anywhere in `lib/`.
    (int, int) retiredFormula(int cmdValue) {
      final outVal = 0x4000 | (cmdValue << 5);
      final hi = (outVal >> 8) & 0xFF;
      final lo = cmdValue > 7 ? (outVal & 0xFF) >> 1 : (outVal & 0xFF);
      return (hi, lo);
    }

    test('unpinned 6-15 encode identically to the retired 0x4000 | (i << 5) formula (the two coincide there)', () {
      for (var i = 6; i <= 15; i++) {
        expect(SourceMapping.selectPayloadBytes(i), retiredFormula(i), reason: 'index $i');
        expect(SourceMapping.encodeSelectPayload(i), retiredFormula(i), reason: 'index $i');
      }
    });

    test('16-29 encode as bfloat16(index): 16 -> 41 80, 29 -> 41 E8 (NOT confirmable on the owner\'s unit, no enabled slot >= 6; the retired formula produced 32.0, 36.0, ... no-ops)', () {
      expect(SourceMapping.selectPayloadBytes(16), (0x41, 0x80));
      expect(SourceMapping.selectPayloadBytes(29), (0x41, 0xE8));
      // End-to-end through the payload builder, so the pinned table cannot
      // shadow the general case for these indices.
      final p16 = CommandPayloads.selectSource(16);
      final p29 = CommandPayloads.selectSource(29);
      expect((p16.byte8, p16.byte9), (0x41, 0x80));
      expect((p29.byte8, p29.byte9), (0x41, 0xE8));
      // The retired formula disagrees here — the whole point of 1.1.4.
      expect(retiredFormula(16), isNot((0x41, 0x80)));
      expect(retiredFormula(29), isNot((0x41, 0xE8)));
    });

    test('the pinned pairs are bytes, not float32(index): slot 0 is NaN and slot 3 is 3.5', () {
      expect(SourceMapping.selectPayloadBytes(0), (0xFF, 0xE0));
      expect(SourceMapping.encodeSelectPayload(0), (0x00, 0x00));
      expect(SourceMapping.selectPayloadBytes(3), (0x40, 0x60));
      expect(SourceMapping.encodeSelectPayload(3), (0x40, 0x40));
    });
  });
}
