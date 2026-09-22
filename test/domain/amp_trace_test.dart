import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_command_sink.dart';
import 'package:devialet_expert_remote_app/domain/amp_trace.dart';
import 'package:devialet_expert_remote_app/networking/devialet_client.dart';

import '../networking/fake_udp_transport.dart';
import 'support/fake_time.dart';

void main() {
  test('line format: prefix, monotonic ms, event, then k=v fields in order', () {
    final clock = FakeClock(const Duration(milliseconds: 1234));
    final lines = <String>[];
    final trace = AmpTrace(lines.add, clock);
    expect(trace.enabled, isTrue);
    trace('rx', {'ip': '192.0.2.22', 'power': 'on', 'raw': 111, 'db': -42.0});
    trace('boot timeout');
    expect(lines, ['[amp] 1234ms rx ip=192.0.2.22 power=on raw=111 db=-42.0', '[amp] 1234ms boot timeout']);
  });

  test('AmpTrace.none is disabled and emits nothing; it is the provider default', () {
    expect(AmpTrace.none.enabled, isFalse);
    AmpTrace.none('rx', {'raw': 111}); // no emitter, no throw
    final container = ProviderContainer.test();
    expect(container.read(ampTraceProvider).enabled, isFalse);
  });

  group('DevialetClientCommandSink traces real sends only (Task 3.5.2)', () {
    late List<String> lines;
    late DevialetClientCommandSink sink;

    setUp(() {
      lines = [];
      sink = DevialetClientCommandSink(
        DevialetClient(transport: FakeUdpTransport()),
        ceilingDb: () => -10,
        trace: AmpTrace(lines.add, FakeClock(const Duration(seconds: 2))),
      );
    });

    test('power and the startup volume emit one line each, before the send', () async {
      await sink.setPower('192.0.2.22', true);
      await sink.sendStartupVolume('192.0.2.22', -40);
      expect(lines, [
        '[amp] 2000ms send power ip=192.0.2.22 on=true',
        '[amp] 2000ms send startupVolume ip=192.0.2.22 db=-40.0 ceiling=-10.0',
      ]);
    });

    test('user volume and mute emit one line each (3.6.0 / 3.7.0); the source stub still emits nothing (3.8)', () async {
      await sink.setVolumeDb('192.0.2.22', -30);
      await sink.setMute('192.0.2.22', true);
      await sink.selectSource('192.0.2.22', 3);
      expect(lines, [
        '[amp] 2000ms send volume ip=192.0.2.22 db=-30.0 ceiling=-10.0',
        '[amp] 2000ms send mute ip=192.0.2.22 muted=true',
      ]);
    });

    test('the default trace is none, so an untraced sink stays silent', () async {
      final quiet = DevialetClientCommandSink(DevialetClient(transport: FakeUdpTransport()), ceilingDb: () => -10);
      expect(quiet.trace.enabled, isFalse);
      await quiet.setPower('192.0.2.22', false);
    });
  });
}
