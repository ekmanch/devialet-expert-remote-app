import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/devialet_client_provider.dart';
import 'package:devialet_expert_remote_app/domain/monotonic_clock.dart';
import 'package:devialet_expert_remote_app/domain/debug/simulated_amp.dart';

import '../../domain/support/fake_time.dart';
import '../../networking/fake_udp_transport.dart';

void main() {
  late FakeClock clock;
  late ManualTicker ticker;

  ProviderContainer make() {
    clock = FakeClock();
    ticker = ManualTicker();
    addTearDown(ticker.close);
    return ProviderContainer.test(
      overrides: [
        devialetTransportProvider.overrideWithValue(FakeUdpTransport()),
        monotonicClockProvider.overrideWithValue(clock),
        staleTickProvider.overrideWithValue(ticker.stream),
        debugCommandSinkOverride,
      ],
    );
  }

  ControlViewState view(ProviderContainer c) => c.read(controlViewStateProvider).copyWith(selectedIp: null);

  for (final scenario in DebugScenario.values.where((s) => s != DebugScenario.notResponding)) {
    test('${scenario.name}: the simulated amp reproduces the fixture through the real ingest path', () {
      final c = make();
      c.read(simulatedAmpProvider.notifier).apply(scenario);
      expect(view(c), ControlViewState.forScenario(scenario));
    });
  }

  test('notResponding: broadcasts stop and the view flips after the real 8 s staleness', () async {
    final c = make();
    final sim = c.read(simulatedAmpProvider.notifier);
    sim.apply(DebugScenario.connected);
    sim.apply(DebugScenario.notResponding);
    expect(view(c).hasAmp, isTrue, reason: 'still within the staleness window');
    clock.advance(const Duration(seconds: 8));
    ticker.tick();
    await Future<void>.delayed(Duration.zero);
    expect(view(c), ControlViewState.forScenario(DebugScenario.notResponding));
    expect(c.read(controlViewStateProvider).selectedIp, '192.0.2.22', reason: 'the choice survives silence');
  });

  group('command-aware behaviour (3.2.x)', () {
    const ip = '192.0.2.22';
    ControlViewState liveView(ProviderContainer c) => c.read(controlViewStateProvider);
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('a volume command within 200 ms of the first On is dropped; later ones end the misreport', () async {
      final c = make();
      final sim = c.read(simulatedAmpProvider.notifier);
      sim.apply(DebugScenario.off);
      await sim.setPower(ip, true);
      clock.set(const Duration(seconds: 16));
      sim.tick();
      expect(sim.amps[ip]!.power, isTrue);
      expect(sim.amps[ip]!.misreporting, isTrue);
      await sim.setVolumeDb(ip, -35); // +0 ms: dropped
      clock.set(const Duration(seconds: 16, milliseconds: 300));
      sim.tick();
      expect(sim.amps[ip]!.misreporting, isTrue, reason: 'the early command never applied');
      await sim.setVolumeDb(ip, -35); // +300 ms: accepted, applies at +400
      clock.set(const Duration(seconds: 16, milliseconds: 400));
      sim.tick();
      expect(sim.amps[ip]!.volumeRaw, 125);
      expect(sim.amps[ip]!.misreporting, isFalse);
    });

    test('full loop: power-on from the owner, boot, misreport held, startup volume sent and confirmed', () async {
      final c = make();
      final sim = c.read(simulatedAmpProvider.notifier);
      final owner = c.read(ampStateProvider.notifier);
      sim.apply(DebugScenario.off);
      expect(liveView(c).power, PowerPhase.off);

      await owner.togglePower();
      expect(liveView(c).power, PowerPhase.booting);
      clock.set(const Duration(seconds: 5));
      sim.tick();
      expect(liveView(c).power, PowerPhase.booting);

      clock.set(const Duration(seconds: 16));
      sim.tick(); // first On packet: pre-shutdown byte
      expect(liveView(c).power, PowerPhase.on);
      expect(liveView(c).volumeDb, -40.0, reason: 'held at the target immediately');

      clock.set(const Duration(seconds: 16, milliseconds: 200));
      sim.tick(); // misreport
      expect(c.read(confirmedAmpStateProvider)!.volumeRaw, 111);
      expect(liveView(c).volumeDb, -40.0);

      clock.set(const Duration(seconds: 16, milliseconds: 400));
      sim.tick();
      expect(sim.amps[ip]!.misreporting, isTrue, reason: 'nothing sent before +500 ms');

      clock.set(const Duration(seconds: 16, milliseconds: 600));
      sim.tick(); // owner sends the startup volume on this ingest
      await settle();
      clock.set(const Duration(seconds: 16, milliseconds: 700));
      sim.tick(); // sim applies it and broadcasts raw 115
      expect(sim.amps[ip]!.misreporting, isFalse);
      expect(c.read(confirmedAmpStateProvider)!.volumeDb, -40.0);
      expect(c.read(ampStateProvider).amps[ip]!.pendingVolumeDb, isNull, reason: 'hold released by confirmation');
      expect(liveView(c).volumeDb, -40.0);
    });

    test('power-off is immediate and remembers the last raw byte for the next boot', () async {
      final c = make();
      final sim = c.read(simulatedAmpProvider.notifier);
      sim.apply(DebugScenario.connected);
      await sim.setPower(ip, false);
      sim.tick();
      expect(liveView(c).power, PowerPhase.off);
      expect(sim.amps[ip]!.preShutdownRaw, 145);
    });
  });

  test('cycle wraps in both directions and starts inactive', () {
    final c = make();
    final sim = c.read(simulatedAmpProvider.notifier);
    expect(sim.isActive, isFalse);
    expect(c.read(controlViewStateProvider).hasAmp, isFalse, reason: 'nothing simulated until the first tap');
    sim.cycle(step: -1);
    expect(c.read(simulatedAmpProvider), DebugScenario.muted);
    sim.cycle();
    expect(c.read(simulatedAmpProvider), DebugScenario.connected);
    expect(sim.isActive, isTrue);
  });
}
