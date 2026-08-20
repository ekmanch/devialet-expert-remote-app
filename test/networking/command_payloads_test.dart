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

    test('Select source Phono (status index 1) = byte6 0x00, byte7 0x05, payload 0x3F 0x80', () {
      final payload = CommandPayloads.selectSource(1);
      expect(payload.byte6, 0x00);
      expect(payload.byte7, 0x05);
      expect(payload.byte8, 0x3F);
      expect(payload.byte9, 0x80);
    });

    test('Select source (other inputs) = byte6 0x00, byte7 0x05', () {
      final payload = CommandPayloads.selectSource(4); // AirPlay
      expect(payload.byte6, 0x00);
      expect(payload.byte7, 0x05);
    });
  });

  group('SourceMapping — status index -> command value table from docs/protocol.md', () {
    test('known indices map to their documented command values', () {
      expect(SourceMapping.commandValueForStatusIndex(0), -1); // Optical 1
      expect(SourceMapping.commandValueForStatusIndex(2), 0); // UPnP
      expect(SourceMapping.commandValueForStatusIndex(3), 3); // Roon Ready
      expect(SourceMapping.commandValueForStatusIndex(4), 4); // AirPlay
      expect(SourceMapping.commandValueForStatusIndex(5), 5); // Spotify
      expect(SourceMapping.commandValueForStatusIndex(14), 14); // Air (Bluetooth)
    });

    test('unmapped indices fall back to the raw status index (unverified per protocol.md)', () {
      expect(SourceMapping.commandValueForStatusIndex(9), 9);
    });

    test('bit-packing formula: outVal = 0x4000 | (cmdValue << 5)', () {
      // cmdValue = 4 (AirPlay), <= 7 so no extra >>1 on lo.
      final (hi, lo) = SourceMapping.encodeSelectPayload(4);
      final outVal = 0x4000 | (4 << 5);
      expect(hi, (outVal >> 8) & 0xFF);
      expect(lo, outVal & 0xFF);
    });

    test('cmdValue > 7 applies the extra >>1 shift on lo (inferred, not confirmed)', () {
      // cmdValue = 14 (Air/Bluetooth), > 7 so lo gets an extra >>1.
      final (hi, lo) = SourceMapping.encodeSelectPayload(14);
      final outVal = 0x4000 | (14 << 5);
      expect(hi, (outVal >> 8) & 0xFF);
      expect(lo, (outVal & 0xFF) >> 1);
    });

    test('negative cmdValue (Optical 1 = -1) encodes without throwing', () {
      final (hi, lo) = SourceMapping.encodeSelectPayload(-1);
      expect(hi, 0xFF);
      expect(lo, 0xE0);
    });
  });
}
