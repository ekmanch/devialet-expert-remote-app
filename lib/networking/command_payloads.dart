import 'command_packet.dart';
import 'source_mapping.dart';
import 'volume_codec.dart';

/// Command-family payload builders — the byte6/byte7/byte8/byte9 values for
/// every [Control]/[Shared] command in `docs/protocol.md`'s command table.
abstract final class CommandPayloads {
  static const powerOn = CommandPayload(byte6: 0x01, byte7: 0x01);
  static const powerOff = CommandPayload(byte6: 0x00, byte7: 0x01);
  static const muteOn = CommandPayload(byte6: 0x01, byte7: 0x07);
  static const muteOff = CommandPayload(byte6: 0x00, byte7: 0x07);

  /// [maxDb] is required — see [VolumeCodec.encodeCommandWord].
  static CommandPayload setVolume(double dbIn, {required double? maxDb}) {
    final word = VolumeCodec.encodeCommandWord(dbIn, maxDb: maxDb);
    return CommandPayload(byte6: 0x00, byte7: 0x04, byte8: (word >> 8) & 0xFF, byte9: word & 0xFF);
  }

  /// Status index 1 uses hardcoded bytes (confirmed on two amps), not the
  /// mapping table. Its name is per-unit (`docs/protocol.md`, "Names are
  /// per-unit") and deliberately not recorded here.
  static const int hardcodedSelectStatusIndex = 1;

  /// Bytes found via Wireshark (per `gnulabis/devimote` issue #2, per code
  /// comment cited in protocol.md). They are `float32(1.0)`'s top half
  /// (verified 2026-09-19) — the same value the float encoding gives, kept
  /// as its own literal because it was the first pair ever confirmed.
  static const _hardcodedSelectPayload = CommandPayload(byte6: 0x00, byte7: 0x05, byte8: 0x3F, byte9: 0x80);

  /// Index 1's literal, then the six pinned pairs, then `bfloat16(index)`
  /// (Task 1.1.4) — see [SourceMapping].
  static CommandPayload selectSource(int statusIndex) {
    if (statusIndex == hardcodedSelectStatusIndex) return _hardcodedSelectPayload;
    final (hi, lo) = SourceMapping.selectPayloadBytes(statusIndex);
    return CommandPayload(byte6: 0x00, byte7: 0x05, byte8: hi, byte9: lo);
  }
}
