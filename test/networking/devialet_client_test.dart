import 'dart:typed_data';

import 'package:devialet_expert_remote_app/networking/command_packet.dart';
import 'package:devialet_expert_remote_app/networking/command_payloads.dart';
import 'package:devialet_expert_remote_app/networking/devialet_client.dart';
import 'package:devialet_expert_remote_app/networking/protocol_constants.dart';
import 'package:devialet_expert_remote_app/networking/status_packet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_udp_transport.dart';
import 'status_packet_test.dart' show buildStatusPacket;

void main() {
  group('DevialetClient — no handshake required', () {
    test('a command can be sent the instant an IP is set, with no prior status received', () async {
      final transport = FakeUdpTransport();
      final client = DevialetClient(transport: transport, deviceIp: '192.168.1.50');

      await client.setPower(true);

      expect(transport.sentPairs, hasLength(1));
    });

    test('sending without a device IP set throws rather than silently no-op-ing', () async {
      final transport = FakeUdpTransport();
      final client = DevialetClient(transport: transport);

      expect(() => client.setPower(true), throwsA(isA<NoDeviceIpSetException>()));
    });
  });

  group('DevialetClient — fire-and-forget, sent twice, no ack', () {
    test('every command is sent to the command port via a single sendTwice() call', () async {
      final transport = FakeUdpTransport();
      final client = DevialetClient(transport: transport, deviceIp: '192.168.1.50');

      await client.setMute(true);

      expect(transport.sentPairs, hasLength(1));
      expect(transport.sentPairs.single.host, '192.168.1.50');
      expect(transport.sentPairs.single.port, DevialetProtocol.commandPort);
    });

    test('the two transmitted copies carry different counter values (Counter caveat)', () async {
      final transport = FakeUdpTransport();
      final client = DevialetClient(transport: transport, deviceIp: '192.168.1.50');

      await client.setMute(true);

      final pair = transport.sentPairs.single;
      expect(pair.first, isNot(equals(pair.second)));

      // Both copies still encode the same logical command bytes (6-9).
      expect(pair.first.sublist(6, 10), pair.second.sublist(6, 10));
      // But their counter bytes (2-5) differ, one increment apart.
      expect(pair.first.sublist(2, 6), isNot(equals(pair.second.sublist(2, 6))));
    });
  });

  group('DevialetClient — source switch forces a follow-up volume set (known-gotchas.md #5)', () {
    test('selectSource always sends select-source THEN a forced -40dB volume set, in order', () async {
      final transport = FakeUdpTransport();
      final client = DevialetClient(transport: transport, deviceIp: '192.168.1.50');

      await client.selectSource(4); // AirPlay

      expect(transport.sentPairs, hasLength(2));

      final selectPayload = CommandPayloads.selectSource(4);
      final expectedVolumePayload = CommandPayloads.setVolume(DevialetClient.sourceSwitchVolumeDb);

      expect(transport.sentPairs[0].first.sublist(6, 10), [
        selectPayload.byte6,
        selectPayload.byte7,
        selectPayload.byte8,
        selectPayload.byte9,
      ]);
      expect(transport.sentPairs[1].first.sublist(6, 10), [
        expectedVolumePayload.byte6,
        expectedVolumePayload.byte7,
        expectedVolumePayload.byte8,
        expectedVolumePayload.byte9,
      ]);
    });

    test('the forced volume is sent for EVERY source, not just some (no source exceptions)', () async {
      for (final index in [0, 1, 2, 3, 4, 5, 14]) {
        final transport = FakeUdpTransport();
        final client = DevialetClient(transport: transport, deviceIp: '192.168.1.50');
        await client.selectSource(index);
        expect(transport.sentPairs, hasLength(2), reason: 'source index $index must still force a volume set');
      }
    });
  });

  group('DevialetClient — status listening', () {
    test('valid status broadcasts are surfaced on statusStream', () async {
      final transport = FakeUdpTransport();
      final client = DevialetClient(transport: transport, deviceIp: '192.168.1.50');

      client.startListening();
      final future = client.statusStream.first;
      transport.emitIncoming(buildStatusPacket(deviceName: 'Test Amp'));

      final status = await future;
      expect(status.deviceName, 'Test Amp');

      await client.dispose();
    });

    test('undersized/malformed packets are dropped and never reach statusStream', () async {
      final transport = FakeUdpTransport();
      final client = DevialetClient(transport: transport, deviceIp: '192.168.1.50');

      final received = <DevialetStatus>[];
      client.startListening();
      final subscription = client.statusStream.listen(received.add);

      transport.emitIncoming(Uint8List(10)); // far too short
      transport.emitIncoming(buildStatusPacket(deviceName: 'Valid'));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.deviceName, 'Valid');

      await subscription.cancel();
      await client.dispose();
    });
  });

  group('DevialetClient — safety clamp (known-gotchas.md #6)', () {
    test('setVolumeDb defaults to clamping at -15.0 dB even if a louder value is requested', () async {
      final transport = FakeUdpTransport();
      final client = DevialetClient(transport: transport, deviceIp: '192.168.1.50');

      await client.setVolumeDb(0.0); // "dangerously loud" per known-gotchas.md

      final sentPayload = transport.sentPairs.single.first.sublist(6, 10);
      final expected = CommandPayloads.setVolume(0.0); // uses the same default clamp
      expect(sentPayload, [expected.byte6, expected.byte7, expected.byte8, expected.byte9]);

      final unclamped = CommandPacket(
        packetCounter: 0,
        commandCounter: 0,
        payload: CommandPayloads.setVolume(0.0, maxDb: 0.0),
      ).encode().sublist(6, 10);
      expect(sentPayload, isNot(unclamped));
    });
  });
}
