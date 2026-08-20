import 'dart:math' as math;

/// Volume dB <-> byte encodings for both directions of the protocol.
///
/// The two directions are **not mathematical inverses** of each other —
/// see `docs/protocol.md`, "Volume dB derivation, both directions". Ported
/// as two separate, literal transcriptions rather than derived from one
/// another.
abstract final class VolumeCodec {
  /// Deliberate safety ceiling (`docs/known-gotchas.md` #6) — the Expert Pro
  /// 140 can reach dangerously loud levels well before the protocol's own
  /// +30dB ceiling. **Do not raise this without re-confirming the safety
  /// rationale with the user first** — this must stay in sync with whatever
  /// the UI layer's volume range allows, once that exists.
  static const double defaultSafetyMaxDb = -15.0;

  /// Custom recursive dB -> byte encoding used for the *command* side only
  /// (`DevialetController.dbConvert()`). Takes `abs(dbValue)`; the sign is
  /// applied separately as a flag bit by [encodeCommandWord].
  ///
  /// Assumes [absDb] is quantized to 0.5dB steps (matching the UI's
  /// 0.5dB/step volume controls) — the recursion bottoms out at exactly 0.0
  /// or 0.5, per the two documented base cases.
  static int dbConvert(double absDb) {
    if (absDb <= 0.0) return 0x0000;
    if (absDb <= 0.5) return 0x3F00;
    final shift = (1 + (math.log(absDb) / math.ln2)).ceil();
    final term = 256 >> shift;
    return term + dbConvert(absDb - 0.5);
  }

  /// Clamps [dbIn] to at most [maxDb] (louder values get pulled down to the
  /// ceiling; quieter values pass through unchanged), then encodes via
  /// [dbConvert] with the sign re-applied as bit 0x8000 for negative values.
  static int encodeCommandWord(double dbIn, {double maxDb = defaultSafetyMaxDb}) {
    final clamped = dbIn > maxDb ? maxDb : dbIn;
    var word = dbConvert(clamped.abs());
    if (clamped < 0) word |= 0x8000;
    return word;
  }

  /// Status-broadcast volume formula — deliberately simpler than, and NOT
  /// the inverse of, [dbConvert]/[encodeCommandWord].
  static double decodeStatusVolume(int rawByte) => (rawByte - 195) / 2.0;
}
