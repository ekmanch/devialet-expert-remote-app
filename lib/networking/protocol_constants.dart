/// Wire-level constants for the Devialet Expert Pro UDP protocol.
///
/// Values and their sources are documented in `docs/protocol.md`. This file
/// covers only [Control]/[Shared]-tagged constants — see that doc's
/// annotations for scope.
abstract final class DevialetProtocol {
  /// Port the amp broadcasts unsolicited status packets on (amp -> app).
  static const int statusPort = 45454;

  /// Port commands are unicast to (app -> amp).
  static const int commandPort = 45455;

  /// Status packets shorter than this are discarded as malformed/irrelevant.
  static const int minStatusPacketLength = 566;

  /// Constant 2-byte header ("Dr" in ASCII) present on every command packet.
  static const List<int> headerMagic = [0x44, 0x72];

  /// Every command packet is allocated at exactly this size, regardless of
  /// command type; bytes beyond the populated header/payload/CRC are padding.
  static const int commandPacketLength = 142;

  /// CRC16 is computed over exactly the first 12 bytes (offsets 0-11) of the
  /// command packet — a fixed constant, not parameterized by packet length.
  static const int crcCoveredLength = 12;
}
