/// Status-broadcast source index -> select-source command value mapping.
///
/// Per `docs/known-gotchas.md` #3, the amp's select-source command does NOT
/// accept the raw status-broadcast index — that was the original bug
/// ("Optical 1 selection played Roon Ready instead"). This table must be
/// ported byte-for-byte, not re-derived from a formula: the mapping is
/// non-linear and only known empirically.
abstract final class SourceMapping {
  /// Status index 1 (Phono) is intentionally excluded here — it uses a
  /// separate hardcoded byte pair (0x3F80), not this table or the bit-packing
  /// formula below. See `CommandPayloads.selectSource`.
  static const Map<int, int> _commandValueByStatusIndex = {
    0: -1, // Optical 1
    2: 0, // UPnP
    3: 3, // Roon Ready
    4: 4, // AirPlay
    5: 5, // Spotify
    14: 14, // Air (Bluetooth)
  };

  /// Unmapped indices (custom/uncommon inputs) fall through to the raw
  /// status index, per protocol.md — unverified for those inputs.
  static int commandValueForStatusIndex(int statusIndex) {
    return _commandValueByStatusIndex[statusIndex] ?? statusIndex;
  }

  /// Bit-packs a resolved command value into the select-source command's
  /// payload bytes. Taken as-is from the reverse-engineered behavior — the
  /// `>> 1` on `lo` when `cmdValue > 7` has no documented rationale
  /// (protocol.md flags this as **inferred, not confirmed**).
  static (int hi, int lo) encodeSelectPayload(int cmdValue) {
    final outVal = 0x4000 | (cmdValue << 5);
    final hi = (outVal >> 8) & 0xFF;
    final lo = cmdValue > 7 ? (outVal & 0xFF) >> 1 : (outVal & 0xFF);
    return (hi, lo);
  }
}
