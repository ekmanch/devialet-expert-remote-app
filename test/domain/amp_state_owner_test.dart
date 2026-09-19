import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_command_sink.dart';
import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/domain/devialet_client_provider.dart';
import 'package:devialet_expert_remote_app/domain/monotonic_clock.dart';
import 'package:devialet_expert_remote_app/networking/status_packet_builder.dart';

import '../networking/fake_udp_transport.dart';
import 'support/fake_time.dart';

class ThrowingCommandSink implements AmpCommandSink {
  @override
  Future<void> setVolumeDb(String ip, double db) async => throw StateError('no route to host');
  @override
  Future<void> setMute(String ip, bool muted) async => throw StateError('no route to host');
  @override
  Future<void> setPower(String ip, bool on) async => throw StateError('no route to host');
  @override
  Future<void> selectSource(String ip, int statusIndex) async => throw StateError('no route to host');
}

class RecordingCommandSink extends NoopCommandSink {
  final List<String> calls = [];
  @override
  Future<void> setVolumeDb(String ip, double db) async => calls.add('volume $ip $db');
  @override
  Future<void> setMute(String ip, bool muted) async => calls.add('mute $ip $muted');
}

void main() {
  late FakeClock clock;
  late ManualTicker ticker;
  late FakeUdpTransport transport;

  ProviderContainer make({AmpCommandSink sink = const NoopCommandSink()}) {
    clock = FakeClock();
    ticker = ManualTicker();
    transport = FakeUdpTransport();
    addTearDown(ticker.close);
    return ProviderContainer.test(
      overrides: [
        devialetTransportProvider.overrideWithValue(transport),
        monotonicClockProvider.overrideWithValue(clock),
        staleTickProvider.overrideWithValue(ticker.stream),
        ampCommandSinkProvider.overrideWithValue(sink),
      ],
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);
  ControlViewState view(ProviderContainer c) => c.read(controlViewStateProvider);
  AmpStateOwner owner(ProviderContainer c) => c.read(ampStateProvider.notifier);

  test('a broadcast on the socket reaches the owner with its sender IP and auto-selects a lone amp', () async {
    final c = make();
    c.read(ampStateProvider);
    transport.emitIncoming(buildStatusPacket(deviceName: 'Real Amp', volumeRaw: 145), from: '192.0.2.5');
    await settle();
    final v = view(c);
    expect(v.hasAmp, isTrue);
    expect(v.selectedAmp!.ip, '192.0.2.5');
    expect(v.selectedAmp!.name, 'Real Amp');
    expect(v.volumeDb, -25.0);
  });

  test('the 1 s tick flips a silent amp to not connected; the next broadcast reconnects', () async {
    final c = make();
    c.read(ampStateProvider);
    transport.emitIncoming(buildStatusPacket(), from: '192.0.2.5');
    await settle();
    owner(c).selectIp('192.0.2.5');
    clock.advance(const Duration(seconds: 8));
    ticker.tick();
    await settle();
    expect(view(c).hasAmp, isFalse);
    expect(view(c).selectedIp, '192.0.2.5');
    transport.emitIncoming(buildStatusPacket(), from: '192.0.2.5');
    await settle();
    expect(view(c).hasAmp, isTrue);
  });

  test('intents write synchronously through the mask and revert after 400 ms with a no-op sink', () async {
    final c = make();
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
    final pending = owner(c).setVolumeDb(-24);
    expect(view(c).volumeDb, -24.0, reason: 'written before the send completes');
    await pending;
    expect(view(c).volumeDb, -24.0);
    clock.advance(const Duration(milliseconds: 400));
    ticker.tick();
    await settle();
    expect(view(c).volumeDb, -25.0, reason: 'nothing confirmed it: display-only until Tasks 3.5–3.9');
  });

  test('a failed send rolls the optimistic value back at once', () async {
    final c = make(sink: ThrowingCommandSink());
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
    await owner(c).toggleMute();
    expect(view(c).isMuted, isFalse);
    await owner(c).setVolumeDb(-30);
    expect(view(c).volumeDb, -25.0);
  });

  test('the sink receives the quantized, clamped value for the selected IP', () async {
    final sink = RecordingCommandSink();
    final c = make(sink: sink);
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
    await owner(c).setVolumeDb(-24.24);
    await owner(c).setVolumeDb(0);
    await owner(c).toggleMute();
    expect(sink.calls, ['volume 192.0.2.22 -24.0', 'volume 192.0.2.22 -15.0', 'mute 192.0.2.22 true']);
  });

  test('five rapid steps accumulate on the displayed value', () async {
    final c = make();
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
    for (var i = 0; i < 5; i++) {
      owner(c).stepVolume(1);
    }
    expect(view(c).volumeDb, -20.0);
  });

  test('gated intents are no-ops while Off and with no amp, including power', () async {
    final c = make();
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
    await owner(c).toggleMute();
    await owner(c).setVolumeDb(-30);
    await owner(c).selectSource(3);
    expect((view(c).isMuted, view(c).volumeDb, view(c).activeSourceIndex), (false, -25.0, 0));

    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.notConnected));
    await owner(c).togglePower();
    expect(view(c).hasAmp, isFalse);
  });

  test('selectSource accepts enabled slots only', () async {
    final c = make();
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
    await owner(c).selectSource(9);
    expect(view(c).activeSourceIndex, 0);
    await owner(c).selectSource(3);
    expect(view(c).activeSourceIndex, 3);
  });

  test('selecting None keeps the list; a manual IP is shown not connected until heard', () async {
    final c = make();
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
    owner(c).selectAmp(null);
    expect(view(c).hasAmp, isFalse);
    expect(view(c).knownAmps.length, 3);
    owner(c).addManualAmp('192.0.2.99');
    expect(view(c).hasAmp, isFalse);
    expect(view(c).selectedIp, '192.0.2.99');
    transport.emitIncoming(buildStatusPacket(deviceName: 'Manual'), from: '192.0.2.99');
    await settle();
    expect(view(c).selectedAmp?.name, 'Manual');
  });

  test('the confirmed channel is never masked', () async {
    final c = make();
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
    await owner(c).setVolumeDb(-24);
    expect(view(c).volumeDb, -24.0);
    expect(c.read(confirmedAmpStateProvider)!.volumeDb, -25.0);
  });

  test('disposing the container stops listening and closes the transport', () async {
    final c = make();
    c.read(ampStateProvider);
    c.dispose();
    await settle();
    expect(transport.closed, isTrue);
  });
}
