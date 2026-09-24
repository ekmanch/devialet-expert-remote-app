import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_command_sink.dart';
import 'package:devialet_expert_remote_app/networking/command_payloads.dart';
import 'package:devialet_expert_remote_app/networking/devialet_client.dart';

import '../networking/fake_udp_transport.dart';

void main() {
  List<int> sentPayload(FakeUdpTransport t) => t.sentPairs.single.first.sublist(6, 10);
  List<int> bytesOf(dynamic p) => [p.byte6, p.byte7, p.byte8, p.byte9];

  test('the startup send is clamped by the ceiling read at send time', () async {
    final transport = FakeUdpTransport();
    var ceiling = -30.0;
    final sink = DevialetClientCommandSink(DevialetClient(transport: transport), ceilingDb: () => ceiling);
    await sink.sendStartupVolume('192.0.2.22', -20);
    expect(sentPayload(transport), bytesOf(CommandPayloads.setVolume(-30, maxDb: null)));
    expect(transport.sentPairs.single.host, '192.0.2.22');

    transport.sentPairs.clear();
    ceiling = -10.0;
    await sink.sendStartupVolume('192.0.2.22', -20);
    expect(sentPayload(transport), bytesOf(CommandPayloads.setVolume(-20, maxDb: null)), reason: 'the new ceiling applies');
  });

  test('a null ceiling is the explicit unbounded send', () async {
    final transport = FakeUdpTransport();
    final sink = DevialetClientCommandSink(DevialetClient(transport: transport), ceilingDb: () => null);
    await sink.sendStartupVolume('192.0.2.22', -5);
    expect(sentPayload(transport), bytesOf(CommandPayloads.setVolume(-5, maxDb: null)));
  });

  test('user volume sends the payload for the ip, clamped by the ceiling read at send time (3.6.0)', () async {
    final transport = FakeUdpTransport();
    var ceiling = -30.0;
    final sink = DevialetClientCommandSink(DevialetClient(transport: transport), ceilingDb: () => ceiling);
    await sink.setVolumeDb('192.0.2.22', -20);
    expect(sentPayload(transport), bytesOf(CommandPayloads.setVolume(-30, maxDb: null)));
    expect(transport.sentPairs.single.host, '192.0.2.22');

    transport.sentPairs.clear();
    ceiling = -10.0;
    await sink.setVolumeDb('192.0.2.23', -20);
    expect(sentPayload(transport), bytesOf(CommandPayloads.setVolume(-20, maxDb: null)));
    expect(transport.sentPairs.single.host, '192.0.2.23');
  });

  test('mute sends its own opcode, no volume word (3.7.0; the two are independent on the wire)', () async {
    final transport = FakeUdpTransport();
    final sink = DevialetClientCommandSink(DevialetClient(transport: transport), ceilingDb: () => -10);
    await sink.setMute('192.0.2.22', true);
    expect(sentPayload(transport), bytesOf(CommandPayloads.muteOn));
    transport.sentPairs.clear();
    await sink.setMute('192.0.2.22', false);
    expect(sentPayload(transport), bytesOf(CommandPayloads.muteOff));
  });

  test('source selection sends select×2 then the post-switch volume×2, clamped by the ceiling read at send time (3.8.0 / 3.8.1)', () async {
    final transport = FakeUdpTransport();
    var ceiling = -10.0;
    final sink = DevialetClientCommandSink(DevialetClient(transport: transport), ceilingDb: () => ceiling);
    await sink.selectSource('192.0.2.22', 3, postSwitchDb: -40);
    expect(transport.sentPairs, hasLength(2));
    expect(transport.sentPairs[0].first.sublist(6, 10), bytesOf(CommandPayloads.selectSource(3)));
    expect(transport.sentPairs[1].first.sublist(6, 10), bytesOf(CommandPayloads.setVolume(-40, maxDb: null)));
    expect(transport.sentPairs.map((p) => p.host), ['192.0.2.22', '192.0.2.22']);

    transport.sentPairs.clear();
    ceiling = -45.0;
    await sink.selectSource('192.0.2.22', 3, postSwitchDb: -40);
    expect(
      transport.sentPairs[1].first.sublist(6, 10),
      bytesOf(CommandPayloads.setVolume(-45, maxDb: null)),
      reason: 'the wire ceiling is the second clamp on the forced volume (gotcha #6)',
    );
  });
}
