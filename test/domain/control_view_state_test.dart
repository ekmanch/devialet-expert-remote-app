import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/control_view_state.dart';

void main() {
  group('command predicates (3.2.1)', () {
    test('commandsAllowed only when connected and On; power also while Off, never while Booting', () {
      final on = ControlViewState.forScenario(DebugScenario.connected);
      final off = ControlViewState.forScenario(DebugScenario.off);
      final booting = ControlViewState.forScenario(DebugScenario.booting);
      final none = ControlViewState.forScenario(DebugScenario.notConnected);
      expect([on, off, booting, none].map((s) => s.commandsAllowed), [true, false, false, false]);
      expect([on, off, booting, none].map((s) => s.powerCommandAllowed), [true, true, false, false]);
      expect(on.volumeGroupEnabled, on.commandsAllowed);
      expect(booting.powerEnabled, booting.powerCommandAllowed);
    });
  });

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
}
