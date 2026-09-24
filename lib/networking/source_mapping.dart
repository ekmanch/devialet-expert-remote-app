import 'dart:typed_data';

/// Status-broadcast source index -> select-source payload bytes.
///
/// Per `docs/known-gotchas.md` #3, the amp's select-source command does NOT
/// accept the raw status-broadcast index as an integer — that was the
/// original bug ("Optical 1 selection played Roon Ready instead", names as
/// configured on the reference amp at the time). What the payload *is* was
/// settled on the real amp on 2026-09-19: the **top 16 bits of
/// `float32(index)`** (the same encoding as the volume word), which the amp
/// truncates toward zero (NaN and negative values select slot 0) — see
/// `docs/protocol.md`, "Source selection encoding".
///
/// Two tiers (Task 1.1.4, 2026-09-24):
/// - [_pinnedPayloadByStatusIndex]: the six byte pairs confirmed on two amps.
///   They are kept as **literal bytes** because two of them are not
///   `bfloat16(index)` — slot 0 is NaN (`FF E0`) and slot 3 is 3.5
///   (`40 60`) — and the amp accepts them all the same. Index 1's `3F 80`
///   lives in `CommandPayloads` as its own literal.
/// - [encodeSelectPayload]: `bfloat16(index)` for everything else. For 6–15
///   it produces the same bytes as the retired `0x4000 | (i << 5)` (+ `>> 1`)
///   formula did, so nothing observable changed there; for 16–29 it now
///   encodes 16.0…29.0 where the old formula produced 32.0, 36.0, … (silent
///   no-ops on the amp). Not confirmable on the owner's unit (no enabled slot
///   ≥ 6), and the status byte's active-source field is 4 bits wide (0–15),
///   so a selection there could never be *confirmed* by a broadcast either.
abstract final class SourceMapping {
  /// Only the numbers are protocol constants. Source names are per-unit
  /// (`docs/protocol.md`, "Names are per-unit"): the amp's live broadcast
  /// (name field at `53 + i·17`) is the only source of a slot's name, so no
  /// name is recorded against an index here.
  static const Map<int, (int hi, int lo)> _pinnedPayloadByStatusIndex = {
    0: (0xFF, 0xE0), // float NaN → slot 0 (confirmed KDE)
    2: (0x40, 0x00), // 2.0
    3: (0x40, 0x60), // 3.5, truncated to 3
    4: (0x40, 0x80), // 4.0
    5: (0x40, 0xA0), // 5.0
    14: (0x41, 0x60), // 14.0 (Galaxy S25 2026-08-20; KDE)
  };

  /// The pinned bytes when the index has them, else the float encoding.
  static (int hi, int lo) selectPayloadBytes(int statusIndex) =>
      _pinnedPayloadByStatusIndex[statusIndex] ?? encodeSelectPayload(statusIndex);

  /// `bfloat16(statusIndex)`: the top two bytes of the IEEE-754 float32 of
  /// the slot index, big-endian.
  static (int hi, int lo) encodeSelectPayload(int statusIndex) {
    final bytes = ByteData(4)..setFloat32(0, statusIndex.toDouble());
    return (bytes.getUint8(0), bytes.getUint8(1));
  }
}
