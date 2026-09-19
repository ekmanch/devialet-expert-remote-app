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

    test('raw-fallback index 9 -> 41 10 (unverified on a real amp per docs/protocol.md)', () {
      final payload = CommandPayloads.selectSource(9);
      expect((payload.byte8, payload.byte9), (0x41, 0x10));
    });
  });

  group('SourceMapping — status index -> command value table from docs/protocol.md', () {
    test('known indices map to their documented command values', () {
      // Numbers only — names are per-unit (docs/protocol.md).
      expect(SourceMapping.commandValueForStatusIndex(0), -1);
      expect(SourceMapping.commandValueForStatusIndex(2), 0);
      expect(SourceMapping.commandValueForStatusIndex(3), 3);
      expect(SourceMapping.commandValueForStatusIndex(4), 4);
      expect(SourceMapping.commandValueForStatusIndex(5), 5);
      expect(SourceMapping.commandValueForStatusIndex(14), 14);
    });

    test('unmapped indices fall back to the raw status index (unverified per protocol.md)', () {
      expect(SourceMapping.commandValueForStatusIndex(9), 9);
    });

    test('bit-packing formula: outVal = 0x4000 | (cmdValue << 5)', () {
      // cmdValue = 4, <= 7 so no extra >>1 on lo.
      final (hi, lo) = SourceMapping.encodeSelectPayload(4);
      final outVal = 0x4000 | (4 << 5);
      expect(hi, (outVal >> 8) & 0xFF);
      expect(lo, outVal & 0xFF);
    });

    test('cmdValue > 7 applies the extra >>1 shift on lo (inferred, not confirmed)', () {
      // cmdValue = 14, > 7 so lo gets an extra >>1.
      final (hi, lo) = SourceMapping.encodeSelectPayload(14);
      final outVal = 0x4000 | (14 << 5);
      expect(hi, (outVal >> 8) & 0xFF);
      expect(lo, (outVal & 0xFF) >> 1);
    });

    test('negative cmdValue (status index 0 = -1) encodes without throwing', () {
      final (hi, lo) = SourceMapping.encodeSelectPayload(-1);
      expect(hi, 0xFF);
      expect(lo, 0xE0);
    });
  });
}
