import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_command_sink.dart';
import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/amp_tracker.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/domain/devialet_client_provider.dart';
import 'package:devialet_expert_remote_app/domain/monotonic_clock.dart';
import 'package:devialet_expert_remote_app/networking/devialet_client.dart';
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
  @override
  Future<void> sendStartupVolume(String ip, double db) async => throw StateError('no route to host');
}

class RecordingCommandSink extends NoopCommandSink {
  RecordingCommandSink({this.clock, this.failStartup = false});

  final FakeClock? clock;
  final bool failStartup;
  final List<String> calls = [];
  final List<Duration> startupSentAt = [];

  @override
  Future<void> setVolumeDb(String ip, double db) async => calls.add('volume $ip $db');
  @override
  Future<void> setMute(String ip, bool muted) async => calls.add('mute $ip $muted');
  @override
  Future<void> setPower(String ip, bool on) async => calls.add('power $ip $on');
  @override
  Future<void> sendStartupVolume(String ip, double db) async {
    calls.add('startup $ip $db');
    if (clock != null) startupSentAt.add(clock!.now());
    if (failStartup) throw StateError('no route to host');
  }
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

  group('power / boot state machine (3.2.x)', () {
    const ip = '192.0.2.22';
    Duration s(int seconds, [int ms = 0]) => Duration(seconds: seconds, milliseconds: ms);

    AmpStatusReport on({double volumeDb = -25}) => syntheticReport(ip: ip, name: 'My Devialet', isPoweredOn: true, volumeDb: volumeDb);
    AmpStatusReport off({double volumeDb = -25}) => syntheticReport(ip: ip, name: 'My Devialet', isPoweredOn: false, volumeDb: volumeDb);

    /// Seeds the Off shape and taps power: a self-initiated boot at t = 0.
    Future<RecordingCommandSink> bootFromOff(ProviderContainer c, RecordingCommandSink sink) async {
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
      await owner(c).togglePower();
      return sink;
    }

    test('an external On (no self-initiated boot) gets no record, no send, no hold', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
      clock.set(s(1));
      owner(c).ingest(on(volumeDb: -42));
      expect(view(c).power, PowerPhase.on);
      expect(view(c).volumeDb, -42.0);
      expect(c.read(ampStateProvider).amps[ip]!.boot, isNull);
      expect(sink.calls, isEmpty);
    });

    test('self-initiated: one power send, Booting through Off broadcasts, repeat taps send nothing and do not extend', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      await bootFromOff(c, sink);
      expect(sink.calls, ['power $ip true']);
      expect(view(c).power, PowerPhase.booting);
      clock.set(s(5));
      owner(c).ingest(off());
      expect(view(c).power, PowerPhase.booting, reason: 'Off broadcasts mid-boot are normal');
      await owner(c).togglePower();
      expect(sink.calls, ['power $ip true'], reason: 'inert while Booting');
      // A booting amp keeps broadcasting Off at 5 Hz (it must stay online).
      clock.set(s(19, 999));
      owner(c).ingest(off());
      expect(view(c).power, PowerPhase.booting);
      clock.set(s(20));
      owner(c).ingest(off());
      expect(view(c).power, PowerPhase.off, reason: 'silent fallback at the 20 s deadline, not extended by the second tap');
      expect(view(c).hasAmp, isTrue);
    });

    test('a late On after the timeout is plain On: no startup send, no hold', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      await bootFromOff(c, sink);
      clock.set(s(20));
      ticker.tick();
      await settle();
      clock.set(s(25));
      owner(c).ingest(on(volumeDb: -42));
      clock.set(s(26));
      owner(c).ingest(on(volumeDb: -42));
      expect(view(c).power, PowerPhase.on);
      expect(view(c).volumeDb, -42.0);
      expect(sink.calls, ['power $ip true']);
    });

    test('self On: target shown at once, −42 recorded not displayed, exactly one startup send at ≥ 500 ms', () async {
      final sink = RecordingCommandSink(clock: clock);
      final c = make(sink: sink);
      await bootFromOff(c, sink);
      clock.set(s(16));
      owner(c).ingest(on(volumeDb: -25)); // first On packet: pre-shutdown byte
      expect(view(c).power, PowerPhase.on);
      expect(view(c).volumeDb, -40.0);
      clock.set(s(16, 200));
      owner(c).ingest(on(volumeDb: -42));
      expect(view(c).volumeDb, -40.0);
      expect(c.read(confirmedAmpStateProvider)!.volumeDb, -42.0);
      clock.set(s(16, 400));
      owner(c).ingest(on(volumeDb: -42));
      expect(sink.calls.where((x) => x.startsWith('startup')), isEmpty, reason: 'nothing before +500 ms (gotcha #9)');
      clock.set(s(16, 600));
      owner(c).ingest(on(volumeDb: -42));
      await settle();
      expect(sink.calls.where((x) => x.startsWith('startup')), ['startup $ip -40.0']);
      expect(sink.startupSentAt.single - s(16), greaterThanOrEqualTo(kStartupVolumeDelay));
      clock.set(s(16, 800));
      owner(c).ingest(on(volumeDb: -42));
      ticker.tick();
      await settle();
      expect(sink.calls.where((x) => x.startsWith('startup')).length, 1, reason: 'sent once');
    });

    test('the hold releases on a confirming push, or at 1500 ms via ingest and via tick', () async {
      for (final viaTick in [false, true]) {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        await bootFromOff(c, sink);
        clock.set(s(16));
        owner(c).ingest(on());
        clock.set(s(16, 200));
        owner(c).ingest(on(volumeDb: -42));
        if (!viaTick) {
          clock.set(s(16, 800));
          owner(c).ingest(on(volumeDb: -40));
          expect(c.read(ampStateProvider).amps[ip]!.pendingVolumeDb, isNull);
          clock.set(s(17));
          owner(c).ingest(on(volumeDb: -41));
          expect(view(c).volumeDb, -41.0);
        } else {
          clock.set(s(17, 499));
          ticker.tick();
          await settle();
          expect(view(c).volumeDb, -40.0);
          clock.set(s(17, 500));
          ticker.tick();
          await settle();
          expect(view(c).volumeDb, -42.0, reason: 'bounded hold: the misreport shows honestly');
        }
      }
    });

    test('a user change inside the window re-targets both the send and the hold', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      await bootFromOff(c, sink);
      clock.set(s(16));
      owner(c).ingest(on());
      clock.set(s(16, 300));
      await owner(c).setVolumeDb(-30);
      expect(view(c).volumeDb, -30.0);
      clock.set(s(16, 600));
      owner(c).ingest(on(volumeDb: -42));
      await settle();
      expect(sink.calls.where((x) => x.startsWith('startup')), ['startup $ip -30.0']);
      expect(view(c).volumeDb, -30.0, reason: 'hold kept at the user value past the 400 ms mask window');
      clock.set(s(16, 800));
      owner(c).ingest(on(volumeDb: -30));
      expect(c.read(ampStateProvider).amps[ip]!.pendingVolumeDb, isNull);
    });

    test('a failed startup send drops the record and the hold, no retry', () async {
      final sink = RecordingCommandSink(failStartup: true);
      final c = make(sink: sink);
      await bootFromOff(c, sink);
      clock.set(s(16));
      owner(c).ingest(on());
      clock.set(s(16, 600));
      owner(c).ingest(on(volumeDb: -42));
      await settle();
      expect(c.read(ampStateProvider).amps[ip]!.boot, isNull);
      expect(view(c).volumeDb, -42.0);
      clock.set(s(16, 800));
      owner(c).ingest(on(volumeDb: -42));
      await settle();
      expect(sink.calls.where((x) => x.startsWith('startup')).length, 1);
    });

    test('power-off after confirmation cancels the deferred send', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      await bootFromOff(c, sink);
      clock.set(s(16));
      owner(c).ingest(on());
      clock.set(s(16, 300));
      await owner(c).togglePower();
      expect(view(c).power, PowerPhase.off);
      clock.set(s(16, 600));
      owner(c).ingest(on(volumeDb: -42));
      await settle();
      expect(sink.calls, ['power $ip true', 'power $ip false']);
    });

    test('the follow-up belongs to the booted amp even after the selection moved', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
      owner(c).ingest(off());
      await owner(c).togglePower();
      owner(c).selectIp('192.0.2.23');
      clock.set(s(16));
      owner(c).ingest(on());
      clock.set(s(16, 600));
      owner(c).ingest(on(volumeDb: -42));
      await settle();
      expect(sink.calls, ['power $ip true', 'startup $ip -40.0']);
    });

    test('an on-tap while an optimistic Off is unconfirmed cancels the Off without a boot record', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
      await owner(c).togglePower();
      expect(view(c).power, PowerPhase.off);
      await owner(c).togglePower();
      expect(view(c).power, PowerPhase.on);
      expect(c.read(ampStateProvider).amps[ip]!.boot, isNull);
      expect(sink.calls, ['power $ip false', 'power $ip true']);
    });

    test('nothing but power is accepted while Booting, and power is inert too', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      await bootFromOff(c, sink);
      await owner(c).setVolumeDb(-30);
      await owner(c).toggleMute();
      await owner(c).selectSource(3);
      await owner(c).togglePower();
      expect(view(c).volumeDb, -25.0);
      expect(view(c).isMuted, isFalse);
      expect(view(c).activeSourceIndex, 0);
      expect(sink.calls, ['power $ip true']);
    });

    test('the startup target is clamped to the range in force when the boot starts', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
      owner(c).setVolumeRange(floorDb: -35);
      await owner(c).togglePower();
      clock.set(s(16));
      owner(c).ingest(on());
      expect(view(c).volumeDb, -35.0);
      clock.set(s(16, 600));
      owner(c).ingest(on(volumeDb: -42));
      await settle();
      expect(sink.calls.last, 'startup $ip -35.0');
    });
  });

  test('disposing the container stops listening and closes the transport', () async {
    final c = make();
    c.read(ampStateProvider);
    c.dispose();
    await settle();
    expect(transport.closed, isTrue);
  });
}
