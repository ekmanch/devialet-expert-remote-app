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

  static CommandPayload setVolume(double dbIn, {double maxDb = VolumeCodec.defaultSafetyMaxDb}) {
    final word = VolumeCodec.encodeCommandWord(dbIn, maxDb: maxDb);
    return CommandPayload(byte6: 0x00, byte7: 0x04, byte8: (word >> 8) & 0xFF, byte9: word & 0xFF);
  }

  /// Status-broadcast index of Phono — hardcoded bytes below, not this table.
  static const int phonoStatusIndex = 1;

  /// Bytes found via Wireshark (per `gnulabis/devimote` issue #2, per code
  /// comment cited in protocol.md) — doesn't follow the general bit-packing
  /// formula, so it's special-cased rather than forced through it.
  static const _phonoPayload = CommandPayload(byte6: 0x00, byte7: 0x05, byte8: 0x3F, byte9: 0x80);

  static CommandPayload selectSource(int statusIndex) {
    if (statusIndex == phonoStatusIndex) return _phonoPayload;
    final cmdValue = SourceMapping.commandValueForStatusIndex(statusIndex);
    final (hi, lo) = SourceMapping.encodeSelectPayload(cmdValue);
    return CommandPayload(byte6: 0x00, byte7: 0x05, byte8: hi, byte9: lo);
  }
}
