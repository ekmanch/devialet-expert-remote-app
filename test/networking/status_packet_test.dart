import 'package:devialet_expert_remote_app/networking/protocol_constants.dart';
import 'package:devialet_expert_remote_app/networking/status_packet.dart';
import 'package:devialet_expert_remote_app/networking/status_packet_builder.dart';
import 'package:flutter_test/flutter_test.dart';

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

  group('buildStatusPacket round-trip', () {
    test('every field written by the builder is read back by tryParse, incl. volumeRaw', () {
      final status = DevialetStatus.tryParse(
        buildStatusPacket(
          deviceName: 'Round Trip',
          sources: [(index: 0, enabled: true, name: 'Optical 1'), (index: 14, enabled: true, name: 'AIR')],
          isPoweredOn: false,
          isMuted: true,
          activeSourceIndex: 14,
          volumeRaw: 145,
        ),
      )!;
      expect(status.deviceName, 'Round Trip');
      expect(status.isPoweredOn, isFalse);
      expect(status.isMuted, isTrue);
      expect(status.activeSourceIndex, 14);
      expect(status.volumeRaw, 145);
      expect(status.volumeDb, -25.0);
      expect(status.sources.where((s) => s.isEnabled).map((s) => s.name), ['Optical 1', 'AIR']);
    });
  });
}
