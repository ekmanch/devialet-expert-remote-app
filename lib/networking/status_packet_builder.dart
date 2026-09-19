import 'dart:convert';
import 'dart:typed_data';

import 'protocol_constants.dart';

/// Builds a synthetic, otherwise-valid status broadcast per the offsets
/// documented in docs/protocol.md, with the given field overrides.
///
/// Lives in `lib/` (not `test/`) because the debug build's simulated amp
/// and the widget-test seeding both feed the state owner through the real
/// packet layout — the encoder is the amp side of the same spec.
/// Pure Dart, no Flutter imports (CLAUDE.md, networking isolation).
Uint8List buildStatusPacket({
  String deviceName = 'My Devialet-ETH',
  List<({int index, bool enabled, String name})> sources = const [],
  bool isPoweredOn = true,
  bool isMuted = false,
  int activeSourceIndex = 4,
  int volumeRaw = 165,
  int totalLength = DevialetProtocol.minStatusPacketLength,
}) {
  // Deliberately allocated large enough to hold every field this helper can
  // write, then truncated to totalLength — so an intentionally-undersized
  // packet (e.g. to test the < 566 byte rejection) doesn't also crash this
  // test helper itself.
  final data = Uint8List(DevialetProtocol.minStatusPacketLength);

  final nameBytes = utf8.encode(deviceName);
  data.setRange(19, 19 + nameBytes.length, nameBytes);

  for (final source in sources) {
    final flagOffset = 52 + source.index * 17;
    final nameOffset = 53 + source.index * 17;
    data[flagOffset] = source.enabled ? 0x31 : 0x30; // ASCII '1' / '0'
    final sourceNameBytes = utf8.encode(source.name);
    data.setRange(nameOffset, nameOffset + sourceNameBytes.length, sourceNameBytes);
  }

  data[562] = isPoweredOn ? 0x80 : 0x00;
  data[563] = ((activeSourceIndex << 2) & 0x3C) | (isMuted ? 0x02 : 0x00);
  data[565] = volumeRaw;

  if (totalLength == data.length) return data;
  final result = Uint8List(totalLength);
  result.setRange(0, totalLength < data.length ? totalLength : data.length, data);
  return result;
}
