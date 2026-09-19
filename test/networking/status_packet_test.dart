import 'dart:convert';
import 'dart:typed_data';

import 'package:devialet_expert_remote_app/networking/protocol_constants.dart';
import 'package:devialet_expert_remote_app/networking/status_packet.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a synthetic, otherwise-valid status broadcast per the offsets
/// documented in docs/protocol.md, with the given field overrides.
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

void main() {
  group('DevialetStatus.tryParse', () {
    test('parses a well-formed synthetic packet correctly', () {
      final data = buildStatusPacket(
        deviceName: 'Living Room Amp',
        sources: [(index: 4, enabled: true, name: 'AirPlay'), (index: 0, enabled: false, name: 'Optical 1')],
        isPoweredOn: true,
        isMuted: true,
        activeSourceIndex: 4,
        volumeRaw: 175, // (175-195)/2.0 = -10.0
      );

      final status = DevialetStatus.tryParse(data);

      expect(status, isNotNull);
      expect(status!.deviceName, 'Living Room Amp');
      expect(status.isPoweredOn, isTrue);
      expect(status.isMuted, isTrue);
      expect(status.activeSourceIndex, 4);
      expect(status.volumeDb, -10.0);
    });

    test('golden vector: volume raw byte 111 decodes to -42.0 dB (docs/protocol.md)', () {
      final status = DevialetStatus.tryParse(buildStatusPacket(volumeRaw: 111))!;
      expect(status.volumeDb, -42.0);
    });

    test('always returns exactly 30 source slots, including disabled/unset ones', () {
      final data = buildStatusPacket(sources: [(index: 4, enabled: true, name: 'AirPlay')]);
      final status = DevialetStatus.tryParse(data)!;

      expect(status.sources, hasLength(30));
      expect(status.sources[4].isEnabled, isTrue);
      expect(status.sources[4].name, 'AirPlay');
      expect(status.sources[0].isEnabled, isFalse);
      expect(status.sources[0].name, isEmpty);
    });

    test('trims NUL and space padding from names', () {
      final data = buildStatusPacket(deviceName: 'Amp\x00\x00\x00   ');
      final status = DevialetStatus.tryParse(data)!;
      expect(status.deviceName, 'Amp');
    });

    test('power bit 0x80 off is decoded as powered off', () {
      final data = buildStatusPacket(isPoweredOn: false);
      expect(DevialetStatus.tryParse(data)!.isPoweredOn, isFalse);
    });

    test('mute bit 0x02 off is decoded as unmuted', () {
      final data = buildStatusPacket(isMuted: false);
      expect(DevialetStatus.tryParse(data)!.isMuted, isFalse);
    });

    test('packets shorter than 566 bytes are dropped (return null), not crashed on', () {
      final data = buildStatusPacket(totalLength: DevialetProtocol.minStatusPacketLength - 1);
      expect(DevialetStatus.tryParse(data), isNull);
    });

    test('exactly 566 bytes is accepted (minimum length is inclusive)', () {
      final data = buildStatusPacket();
      expect(data.length, DevialetProtocol.minStatusPacketLength);
      expect(DevialetStatus.tryParse(data), isNotNull);
    });

    test('excess bytes beyond the parsed fields are simply ignored', () {
      final data = buildStatusPacket(totalLength: 2048);
      expect(DevialetStatus.tryParse(data), isNotNull);
    });
  });
}
