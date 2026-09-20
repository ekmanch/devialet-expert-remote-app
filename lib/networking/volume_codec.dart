import 'dart:math' as math;

/// Volume dB <-> byte encodings for both directions of the protocol.
///
/// The two directions are **not mathematical inverses** of each other —
/// see `docs/protocol.md`, "Volume dB derivation, both directions". Ported
/// as two separate, literal transcriptions rather than derived from one
/// another.
abstract final class VolumeCodec {
  /// Custom recursive dB -> byte encoding used for the *command* side only
  /// (`DevialetController.dbConvert()`). Takes `abs(dbValue)`; the sign is
  /// applied separately as a flag bit by [encodeCommandWord].
  ///
  /// [absDb] is quantized to the **nearest** 0.5 dB step once, here, and the
  /// recursion then runs on an integer step count (ported from the KDE
  /// widget's `db_convert` — `docs/protocol.md`, "Port-critical —
  /// non-half-step input"). Byte-identical to the literal Kotlin float
  /// recursion on every exact step; on off-grid input it rounds to nearest
  /// rather than up, so upward float drift can never send 0.5 dB louder
  /// than intended. Negative input collapses to 0 steps.
  static int dbConvert(double absDb) {
    final steps = math.max(0, (absDb / 0.5).round());
    return _dbConvertSteps(steps);
  }

  static int _dbConvertSteps(int steps) {
    switch (steps) {
      case 0:
        return 0x0000;
      case 1:
        return 0x3F00;
      default:
        // Re-derived at the exact grid value so the log2 term is never
        // evaluated on an accumulated `absDb - 0.5 - 0.5 …` float.
        final dbAbs = steps * 0.5;
        final shift = (1 + math.log(dbAbs) / math.ln2).ceil();
        // Fail safe (term 0) outside the range the formula was ever
        // exercised at, instead of throwing on a negative/oversized shift.
        final term = (shift >= 0 && shift < 32) ? 256 >> shift : 0;
        return (term + _dbConvertSteps(steps - 1)) & 0xFFFF;
    }
  }

  /// Clamps [dbIn] to at most [maxDb] (louder values get pulled down to the
  /// ceiling; quieter values pass through unchanged), then encodes via
  /// [dbConvert] with the sign re-applied as bit 0x8000 for negative values.
  ///
  /// [maxDb] is **required** (Task 1.1.3, checklist item 28): the Expert Pro
  /// 140 reaches dangerously loud levels well before the protocol's own
  /// +30 dB (`docs/known-gotchas.md` #6), so no caller can forget the
  /// ceiling. The app passes the persisted settings ceiling
  /// (`AppSettings.defaults.ceilingDb`, −10); `null` is the explicit
  /// "no ceiling" and must be spelled out by the caller.
  static int encodeCommandWord(double dbIn, {required double? maxDb}) {
    final clamped = maxDb != null && dbIn > maxDb ? maxDb : dbIn;
    var word = dbConvert(clamped.abs());
    if (clamped < 0) word |= 0x8000;
    return word;
  }

  /// Status-broadcast volume formula — deliberately simpler than, and NOT
  /// the inverse of, [dbConvert]/[encodeCommandWord].
  static double decodeStatusVolume(int rawByte) => (rawByte - 195) / 2.0;
}
