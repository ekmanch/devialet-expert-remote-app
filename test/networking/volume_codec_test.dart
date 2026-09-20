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

  group('VolumeCodec.dbConvert golden vectors (docs/protocol.md)', () {
    // Exact-step inputs; output must stay byte-identical across any
    // quantization change (TODO.md, "Quantize to the nearest 0.5 dB").
    test('dbConvert(1.0) == 0x3F80', () {
      expect(VolumeCodec.dbConvert(1.0), 0x3F80);
    });

    test('dbConvert(15.0) == 0x4170', () {
      expect(VolumeCodec.dbConvert(15.0), 0x4170);
    });

    test('dbConvert(40.0) == 0x4220', () {
      expect(VolumeCodec.dbConvert(40.0), 0x4220);
    });

    test('remaining exact-step vectors from the KDE reference suite', () {
      // crates/protocol/src/dbconvert.rs, matches_reference_at_exact_half_db_steps.
      expect(VolumeCodec.dbConvert(1.5), 0x3FC0);
      expect(VolumeCodec.dbConvert(2.0), 0x4000);
      expect(VolumeCodec.dbConvert(4.0), 0x4080);
      expect(VolumeCodec.dbConvert(8.0), 0x4100);
    });
  });

  group('VolumeCodec.dbConvert non-half-step rounding', () {
    // TODO.md, "Quantize to the nearest 0.5 dB before dbConvert": input
    // that is not on the 0.5 dB grid must round to the *nearest* step, not
    // up, so upward float drift never sends 0.5 dB louder than intended.
    const golden15 = 0x4170;

    test('15.0000001 rounds to nearest (15.0), not up to 15.5', () {
      expect(VolumeCodec.dbConvert(15.0000001), golden15);
    });

    test('14.9999999 rounds to nearest (15.0) from below', () {
      expect(VolumeCodec.dbConvert(14.9999999), golden15);
    });

    test('15.3 rounds to the nearest 0.5 dB step (15.5), not 15.0 or 16.0', () {
      final expected = VolumeCodec.dbConvert(15.5);
      expect(expected, isNot(VolumeCodec.dbConvert(15.0)));
      expect(expected, isNot(VolumeCodec.dbConvert(16.0)));
      expect(VolumeCodec.dbConvert(15.3), expected);
    });

    test('15.7 rounds to 15.5 (grid is 0.5 dB, not 1.0 dB)', () {
      final expected = VolumeCodec.dbConvert(15.5);
      expect(expected, isNot(VolumeCodec.dbConvert(16.0)));
      expect(VolumeCodec.dbConvert(15.7), expected);
    });

    test('rounds to nearest at the lowest step boundary (0.25)', () {
      expect(VolumeCodec.dbConvert(0.24), 0x0000);
      expect(VolumeCodec.dbConvert(0.26), 0x3F00);
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
      const ceiling = -15.0;
      final clampedWord = VolumeCodec.encodeCommandWord(-40.0, maxDb: ceiling);
      final direct = VolumeCodec.encodeCommandWord(0.0, maxDb: ceiling);
      // Requesting 0dB (too loud) must clamp to exactly the same word as
      // requesting the ceiling directly.
      expect(direct, VolumeCodec.dbConvert(ceiling.abs()) | 0x8000);
      // A quieter request must NOT be clamped.
      expect(clampedWord, isNot(direct));
    });

    test('the ceiling is required; null is the explicit "unbounded" and passes everything through', () {
      // The parameter being required is enforced by the analyzer (a call
      // without `maxDb:` does not compile — Task 1.1.3, checklist 28).
      expect(VolumeCodec.encodeCommandWord(0.0, maxDb: null), 0x0000);
      expect(VolumeCodec.encodeCommandWord(30.0, maxDb: null), VolumeCodec.dbConvert(30.0));
      expect(VolumeCodec.encodeCommandWord(-5.0, maxDb: -10.0), VolumeCodec.dbConvert(10.0) | 0x8000);
    });
  });

  group('VolumeCodec.decodeStatusVolume', () {
    test('applies the documented (raw - 195) / 2.0 formula', () {
      expect(VolumeCodec.decodeStatusVolume(195), 0.0);
      expect(VolumeCodec.decodeStatusVolume(165), -15.0);
      expect(VolumeCodec.decodeStatusVolume(255), 30.0);
      expect(VolumeCodec.decodeStatusVolume(111), -42.0);
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
