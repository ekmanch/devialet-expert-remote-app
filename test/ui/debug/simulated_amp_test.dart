import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/devialet_client_provider.dart';
import 'package:devialet_expert_remote_app/domain/monotonic_clock.dart';
import 'package:devialet_expert_remote_app/ui/debug/simulated_amp.dart';

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
