import 'package:devialet_expert_remote_app/networking/volume_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VolumeCodec.dbConvert', () {
    // Exact example byte values given in docs/protocol.md.
    test('dbConvert(0.0) == 0x0000', () {
      expect(VolumeCodec.dbConvert(0.0), 0x0000);
    });

    test('dbConvert(0.5) == 0x3F00', () {
      expect(VolumeCodec.dbConvert(0.5), 0x3F00);
    });

    test('is monotonically non-decreasing as magnitude grows', () {
      var previous = VolumeCodec.dbConvert(0.0);
      for (var db = 0.5; db <= 30.0; db += 0.5) {
        final value = VolumeCodec.dbConvert(db);
        expect(value, greaterThanOrEqualTo(previous));
        previous = value;
      }
    });
  });

  group('VolumeCodec.encodeCommandWord', () {
    test('0.0 dB encodes with no sign bit set', () {
      expect(VolumeCodec.encodeCommandWord(0.0, maxDb: 0.0), 0x0000);
    });

    test('negative dB sets the 0x8000 sign bit on top of the magnitude', () {
      final magnitude = VolumeCodec.dbConvert(20.0);
      expect(VolumeCodec.encodeCommandWord(-20.0, maxDb: 0.0), magnitude | 0x8000);
    });

    test('values louder than maxDb are clamped down to maxDb (known-gotchas.md #6)', () {
      final clampedWord = VolumeCodec.encodeCommandWord(-40.0, maxDb: VolumeCodec.defaultSafetyMaxDb);
      final direct = VolumeCodec.encodeCommandWord(0.0, maxDb: VolumeCodec.defaultSafetyMaxDb);
      // Requesting 0dB (too loud) must clamp to exactly the same word as
      // requesting the safety ceiling directly.
      expect(direct, VolumeCodec.dbConvert(VolumeCodec.defaultSafetyMaxDb.abs()) | 0x8000);
      // A quieter request must NOT be clamped.
      expect(clampedWord, isNot(direct));
    });

    test('default safety ceiling is -15.0 dB and is not silently regressed', () {
      expect(VolumeCodec.defaultSafetyMaxDb, -15.0);
    });
  });

  group('VolumeCodec.decodeStatusVolume', () {
    test('applies the documented (raw - 195) / 2.0 formula', () {
      expect(VolumeCodec.decodeStatusVolume(195), 0.0);
      expect(VolumeCodec.decodeStatusVolume(165), -15.0);
      expect(VolumeCodec.decodeStatusVolume(255), 30.0);
    });

    test('is not the inverse of the command-side encoding', () {
      // Deliberately cross-checking that decode(encode(x)) is NOT identity —
      // protocol.md explicitly warns these are independent encodings.
      final word = VolumeCodec.encodeCommandWord(-15.0, maxDb: 0.0);
      final decodedAsIfStatusByte = VolumeCodec.decodeStatusVolume(word & 0xFF);
      expect(decodedAsIfStatusByte, isNot(-15.0));
    });
  });
}
