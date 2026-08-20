import 'dart:typed_data';

import 'crc16.dart';
import 'protocol_constants.dart';

/// The command-specific bytes 6-9 of a command packet (family selector,
/// sub-selector, and a 2-byte payload). See `docs/protocol.md` command table.
class CommandPayload {
  const CommandPayload({
    required this.byte6,
    required this.byte7,
    this.byte8 = 0x00,
    this.byte9 = 0x00,
  });

  final int byte6;
  final int byte7;
  final int byte8;
  final int byte9;
}

/// Builds the fixed 142-byte command packet described in `docs/protocol.md`
/// ("Command packet structure"). Offsets 10-11 and 14-141 are left
/// zero-filled (unused/padding), matching the documented layout exactly.
class CommandPacket {
  const CommandPacket({
    required this.packetCounter,
    required this.commandCounter,
    required this.payload,
  });

  final int packetCounter;
  final int commandCounter;
  final CommandPayload payload;

  Uint8List encode() {
    final bytes = Uint8List(DevialetProtocol.commandPacketLength);
    bytes[0] = DevialetProtocol.headerMagic[0];
    bytes[1] = DevialetProtocol.headerMagic[1];
    bytes[2] = (packetCounter >> 8) & 0xFF;
    bytes[3] = packetCounter & 0xFF;
    bytes[4] = (commandCounter >> 8) & 0xFF;
    bytes[5] = commandCounter & 0xFF;
    bytes[6] = payload.byte6;
    bytes[7] = payload.byte7;
    bytes[8] = payload.byte8;
    bytes[9] = payload.byte9;
    // Offsets 10-11 stay zero (unused).
    final crc = crc16CcittFalse(bytes, length: DevialetProtocol.crcCoveredLength);
    bytes[12] = (crc >> 8) & 0xFF;
    bytes[13] = crc & 0xFF;
    // Offsets 14-141 stay zero (padding).
    return bytes;
  }
}
