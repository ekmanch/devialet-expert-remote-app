import 'dart:typed_data';

import 'package:devialet_expert_remote_app/networking/crc16.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('crc16CcittFalse', () {
    test('all-zero input over 12 bytes matches an independently-computed reference value', () {
      // Reference value computed separately in Python (CRC16/CCITT-FALSE,
      // poly 0x1021, init 0xFFFF, no final XOR) over 12 zero bytes.
      final data = Uint8List(12);
      expect(crc16CcittFalse(data, length: 12), 0x84F9);
    });

    test('empty-length computation returns the untouched initial value', () {
      final data = Uint8List(12);
      expect(crc16CcittFalse(data, length: 0), 0xFFFF);
    });

    test('only reads the first `length` bytes, ignoring the rest', () {
      final short = Uint8List(12);
      final padded = Uint8List(142); // rest is garbage/padding beyond byte 12
      for (var i = 12; i < 142; i++) {
        padded[i] = 0xAB;
      }
      expect(crc16CcittFalse(padded, length: 12), crc16CcittFalse(short, length: 12));
    });

    test('changing a covered byte changes the result to the expected reference value', () {
      final a = Uint8List(12);
      final b = Uint8List(12)..[5] = 0x01;
      expect(crc16CcittFalse(a, length: 12), isNot(crc16CcittFalse(b, length: 12)));
      expect(crc16CcittFalse(b, length: 12), 0x3C98);
    });
  });
}
