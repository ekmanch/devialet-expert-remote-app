import 'dart:typed_data';

/// CRC16/CCITT-FALSE: polynomial 0x1021, initial value 0xFFFF, no final XOR.
///
/// Computed over [length] bytes of [data] starting at offset 0. Per
/// `docs/protocol.md`, the command packet always covers exactly the first 12
/// bytes regardless of overall packet length.
int crc16CcittFalse(Uint8List data, {required int length}) {
  var crc = 0xFFFF;
  for (var i = 0; i < length; i++) {
    crc ^= data[i] << 8;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) & 0xFFFF : (crc << 1) & 0xFFFF;
    }
  }
  return crc & 0xFFFF;
}
