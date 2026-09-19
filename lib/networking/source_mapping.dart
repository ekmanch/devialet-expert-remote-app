/// Status-broadcast source index -> select-source command value mapping.
///
/// Per `docs/known-gotchas.md` #3, the amp's select-source command does NOT
/// accept the raw status-broadcast index — that was the original bug
/// ("Optical 1 selection played Roon Ready instead", names as configured on
/// the reference amp at the time). The seven table entries are kept as
/// literal bytes (confirmed on two amps). What they *are* was settled on
/// the real amp on 2026-09-19: the payload is the top 16 bits of
/// `float32(index)`, which the amp truncates toward zero (NaN and negative
/// values select slot 0) — see `docs/protocol.md`, "Source selection
/// encoding".
abstract final class SourceMapping {
  /// Status index 1 is intentionally excluded here — it uses a separate
  /// hardcoded byte pair (0x3F80), not this table or the bit-packing formula
  /// below. See `CommandPayloads.selectSource`.
  ///
  /// Only the numbers are protocol constants. Source names are per-unit
  /// (`docs/protocol.md`, "Names are per-unit"): the amp's live broadcast
  /// (name field at `53 + i·17`) is the only source of a slot's name, so no
  /// name is recorded against an index here.
  static const Map<int, int> _commandValueByStatusIndex = {
    0: -1,
    2: 0,
    3: 3,
    4: 4,
    5: 5,
    14: 14,
  };

  /// Unmapped indices (custom/uncommon inputs) fall through to the raw
  /// status index. Correct for 6-15 only: the packing below yields 32.0,
  /// 36.0, … for indices >= 16, which the amp ignores (Task 1.1.4).
  static int commandValueForStatusIndex(int statusIndex) {
    return _commandValueByStatusIndex[statusIndex] ?? statusIndex;
  }

  /// Bit-packs a resolved command value into the select-source command's
  /// payload bytes. Taken as-is from the reverse-engineered behavior. The
  /// `>> 1` on `lo` when `cmdValue > 7` is explained (verified 2026-09-19):
  /// for 8-15 the halved low byte lands exactly on the top 16 bits of
  /// `float32(cmdValue)`, which is what the amp actually decodes; for >= 16
  /// the formula produces 32.0, 36.0, … and the amp does nothing.
  static (int hi, int lo) encodeSelectPayload(int cmdValue) {
    final outVal = 0x4000 | (cmdValue << 5);
    final hi = (outVal >> 8) & 0xFF;
    final lo = cmdValue > 7 ? (outVal & 0xFF) >> 1 : (outVal & 0xFF);
    return (hi, lo);
  }
}
