import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state_provider.dart';

void main() {
  ControlViewNotifier notifierFor(ProviderContainer c) => c.read(controlViewStateProvider.notifier);
  ControlViewState stateOf(ProviderContainer c) => c.read(controlViewStateProvider);

  ProviderContainer container({DebugScenario scenario = DebugScenario.connected}) {
    final c = ProviderContainer.test(
      overrides: [
        controlViewStateProvider.overrideWith(() => ControlViewNotifier(initialScenario: scenario)),
      ],
    );
    return c;
  }

  group('scenario fixtures', () {
    test('connected: amp, on, unmuted, −25 in −60..−15, six sources', () {
      final s = ControlViewState.forScenario(DebugScenario.connected);
      expect(s.hasAmp, isTrue);
      expect(s.volumeGroupEnabled, isTrue);
      expect(s.powerEnabled, isTrue);
      expect(s.volumeDb, -25.0);
      expect((s.floorDb, s.ceilingDb), (-60.0, -15.0));
      expect(s.sources.length, 6);
      expect(s.activeSource?.name, 'Optical 1');
      expect(s.selectedAmp!.ip, startsWith('192.0.2.'), reason: 'fixtures use TEST-NET-1 only');
    });

    test('off / booting keep last-known volume and gate everything but power', () {
      for (final scenario in [DebugScenario.off, DebugScenario.booting]) {
        final s = ControlViewState.forScenario(scenario);
        expect(s.hasAmp, isTrue);
        expect(s.ampInert, isTrue);
        expect(s.volumeGroupEnabled, isFalse);
        expect(s.volumeDb, -25.0);
        expect(s.powerEnabled, scenario == DebugScenario.off);
      }
    });

    test('notResponding and notConnected both present as no amp', () {
      for (final scenario in [DebugScenario.notResponding, DebugScenario.notConnected]) {
        final s = ControlViewState.forScenario(scenario);
        expect(s.hasAmp, isFalse);
        expect(s.selectedAmp, isNull);
        expect(s.sources, isEmpty);
        expect(s.activeSource, isNull);
        expect(s.volumeGroupEnabled, isFalse);
        expect(s.powerEnabled, isFalse);
      }
      expect(ControlViewState.forScenario(DebugScenario.notResponding).knownAmps, isEmpty);
      expect(ControlViewState.forScenario(DebugScenario.notConnected).knownAmps, isNotEmpty);
    });

    test('muted', () {
      expect(ControlViewState.forScenario(DebugScenario.muted).isMuted, isTrue);
    });

    test('copyWith can clear nullable fields', () {
      final s = ControlViewState.connectedFixture.copyWith(selectedAmp: null, activeSourceIndex: null);
      expect(s.selectedAmp, isNull);
      expect(s.activeSourceIndex, isNull);
      expect(s.copyWith().selectedAmp, isNull);
    });
  });

  group('ControlViewNotifier', () {
    test('cycleScenario wraps in both directions', () {
      final c = container(scenario: DebugScenario.muted);
      notifierFor(c).cycleScenario();
      expect(notifierFor(c).scenario, DebugScenario.connected);
      notifierFor(c).cycleScenario(step: -1);
      expect(notifierFor(c).scenario, DebugScenario.muted);
      expect(stateOf(c).isMuted, isTrue);
    });

    test('power: on → off → booting → (stays booting)', () {
      final c = container();
      notifierFor(c).togglePower();
      expect(stateOf(c).power, PowerPhase.off);
      notifierFor(c).togglePower();
      expect(stateOf(c).power, PowerPhase.booting);
      notifierFor(c).togglePower();
      expect(stateOf(c).power, PowerPhase.booting);
    });

    test('volume clamps to floor/ceiling and steps by 1 dB', () {
      final c = container();
      notifierFor(c).setVolumeDb(0);
      expect(stateOf(c).volumeDb, -15.0);
      notifierFor(c).setVolumeDb(-99);
      expect(stateOf(c).volumeDb, -60.0);
      notifierFor(c).setVolumeDb(-25);
      notifierFor(c).stepVolume(1);
      expect(stateOf(c).volumeDb, -24.0);
      notifierFor(c).stepVolume(-1, stepDb: 0.5);
      expect(stateOf(c).volumeDb, -24.5);
    });

    test('gated intents are no-ops while Off', () {
      final c = container(scenario: DebugScenario.off);
      final before = stateOf(c);
      notifierFor(c)
        ..toggleMute()
        ..setVolumeDb(-30)
        ..stepVolume(1)
        ..selectSource(3);
      expect(stateOf(c).isMuted, before.isMuted);
      expect(stateOf(c).volumeDb, before.volumeDb);
      expect(stateOf(c).activeSourceIndex, before.activeSourceIndex);
    });

    test('gated intents are no-ops with no amp, including power', () {
      final c = container(scenario: DebugScenario.notConnected);
      notifierFor(c)
        ..togglePower()
        ..toggleMute()
        ..setVolumeDb(-30);
      expect(stateOf(c).hasAmp, isFalse);
      expect(stateOf(c).power, PowerPhase.on);
    });

    test('selectSource only accepts an enabled slot', () {
      final c = container();
      notifierFor(c).selectSource(3);
      expect(stateOf(c).activeSource?.name, 'AirPlay');
      notifierFor(c).selectSource(9);
      expect(stateOf(c).activeSourceIndex, 3);
    });

    test('selectAmp(null) is None; selecting an amp lands on on/unmuted', () {
      final c = container(scenario: DebugScenario.muted);
      notifierFor(c).selectAmp(null);
      expect(stateOf(c).hasAmp, isFalse);
      expect(stateOf(c).knownAmps, isNotEmpty, reason: 'None keeps the discovered list');
      notifierFor(c).selectAmp(ControlViewState.fixtureAmps[1]);
      expect(stateOf(c).selectedAmp!.displayName, 'Devialet Expert 220 Pro');
      expect(stateOf(c).isMuted, isFalse);
      expect(stateOf(c).power, PowerPhase.on);
      expect(stateOf(c).sources, isNotEmpty);
    });

    test('addManualAmp prepends an unresolved amp and selects it', () {
      final c = container(scenario: DebugScenario.notConnected);
      notifierFor(c).addManualAmp('192.0.2.9');
      final s = stateOf(c);
      expect(s.knownAmps.first.ip, '192.0.2.9');
      expect(s.knownAmps.first.isResolved, isFalse);
      expect(s.selectedAmp, s.knownAmps.first);
      expect(s.hasAmp, isTrue);
    });
  });
}
