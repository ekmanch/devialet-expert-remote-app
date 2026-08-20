import 'package:devialet_expert_remote_app/networking/command_packet.dart';
import 'package:devialet_expert_remote_app/networking/crc16.dart';
import 'package:devialet_expert_remote_app/networking/protocol_constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CommandPacket.encode', () {
    const payload = CommandPayload(byte6: 0x01, byte7: 0x07, byte8: 0xAB, byte9: 0xCD);
    final packet = CommandPacket(packetCounter: 0x1234, commandCounter: 0x5678, payload: payload);
    final bytes = packet.encode();

    test('is always exactly 142 bytes', () {
      expect(bytes.length, DevialetProtocol.commandPacketLength);
    });

    test('starts with the constant "Dr" magic header', () {
      expect(bytes[0], 0x44);
      expect(bytes[1], 0x72);
    });

    test('writes both counters big-endian at offsets 2-5', () {
      expect(bytes[2], 0x12);
      expect(bytes[3], 0x34);
      expect(bytes[4], 0x56);
      expect(bytes[5], 0x78);
    });

    test('writes the command payload at offsets 6-9', () {
      expect(bytes[6], 0x01);
      expect(bytes[7], 0x07);
      expect(bytes[8], 0xAB);
      expect(bytes[9], 0xCD);
    });

    test('leaves offsets 10-11 zero', () {
      expect(bytes[10], 0x00);
      expect(bytes[11], 0x00);
    });

    test('writes a CRC16/CCITT-FALSE over bytes 0-11 at offsets 12-13', () {
      final expectedCrc = crc16CcittFalse(bytes, length: 12);
      expect(bytes[12], (expectedCrc >> 8) & 0xFF);
      expect(bytes[13], expectedCrc & 0xFF);
    });

    test('leaves offsets 14-141 as zero padding', () {
      for (var i = 14; i < 142; i++) {
        expect(bytes[i], 0x00, reason: 'byte $i should be zero padding');
      }
    });
  });
}
