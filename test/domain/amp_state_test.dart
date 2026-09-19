import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_state.dart';
import 'package:devialet_expert_remote_app/domain/amp_tracker.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/networking/devialet_client.dart';

import 'support/status_fixtures.dart';

const amp1 = '192.0.2.22';
const amp2 = '192.0.2.23';
Duration ms(int v) => Duration(milliseconds: v);

/// "Apply every broadcast unconditionally" — the Kotlin-era behaviour behind
/// gotchas #1/#2. Used to prove the masked assertions would fail without
/// the mask (checklist item 20).
AmpState applyUnmasked(AmpState s, AmpStatusReport r, Duration now) => s
    .ingest(r, now)
    .updateAmp(
      r.senderIp,
      (a) => a.copyWith(pendingVolumeDb: null, pendingMuted: null, pendingPower: null, pendingSource: null),
    );

AmpState arm(AmpState s, String ip, TrackedAmp Function(TrackedAmp) write) => s.updateAmp(ip, write);

void main() {
  group('derivation', () {
    test('connected shape from one online amp (auto-selected when never chosen)', () {
      final s = AmpState.initial.ingest(reportFrom(amp1, volumeDb: -25, active: 3), ms(0));
      final v = deriveControlView(s);
      expect(v.connection, ConnectionPhase.connected);
      expect(v.selectedAmp, const AmpRef(id: amp1, name: 'My Devialet-ETH', ip: amp1));
      expect(v.knownAmps.map((a) => a.ip), [amp1]);
      expect(v.power, PowerPhase.on);
      expect(v.isMuted, isFalse);
      expect(v.volumeDb, -25.0);
      expect(v.sources, const [SourceItem(index: 0, name: 'Optical 1'), SourceItem(index: 3, name: 'AirPlay')]);
      expect(v.activeSourceIndex, 3);
      expect((v.floorDb, v.ceilingDb), (kDefaultFloorDb, kDefaultCeilingDb));
      expect(v.hasAmp, isTrue);
    });

    test('not-connected shape carries no reading (floor sentinel) and empty sources', () {
      final v = deriveControlView(AmpState.initial);
      expect(v.connection, ConnectionPhase.notConnected);
      expect(v.selectedAmp, isNull);
      expect(v.hasAmp, isFalse);
      expect(v.power, PowerPhase.off);
      expect(v.sources, isEmpty);
      expect(v.activeSourceIndex, isNull);
      expect(v.volumeDb, v.floorDb);
    });

    test('known amps are online-only and sorted numerically by IP', () {
      var s = AmpState.initial
          .ingest(reportFrom('192.0.2.100', name: 'C'), ms(0))
          .ingest(reportFrom('192.0.2.9', name: 'B'), ms(0))
          .ingest(reportFrom('192.0.2.23', name: 'A'), ms(0));
      expect(deriveControlView(s).knownAmps.map((a) => a.ip), ['192.0.2.9', '192.0.2.23', '192.0.2.100']);
      s = s.tick(ms(0) + kStaleAfter).ingest(reportFrom('192.0.2.9', name: 'B'), ms(0) + kStaleAfter);
      expect(deriveControlView(s).knownAmps.map((a) => a.ip), ['192.0.2.9'], reason: 'silent ones hidden, not evicted');
      expect(s.amps.length, 3);
    });

    test('power: booting while a boot deadline is pending, cleared by a late On', () {
      var s = AmpState.initial.ingest(reportFrom(amp1, power: false), ms(0));
      s = arm(s, amp1, (a) => a.copyWith(bootDeadline: ms(0) + kBootTimeout));
      expect(deriveControlView(s).power, PowerPhase.booting);
      s = s.ingest(reportFrom(amp1, power: false), ms(5000));
      expect(deriveControlView(s).power, PowerPhase.booting, reason: 'an Off broadcast mid-boot is normal');
      s = s.ingest(reportFrom(amp1, power: true), ms(16000));
      expect(deriveControlView(s).power, PowerPhase.on);
      expect(s.amps[amp1]!.bootDeadline, isNull);
    });

    test('power: boot deadline expiring with no On falls back to Off', () {
      var s = AmpState.initial.ingest(reportFrom(amp1, power: false), ms(0));
      s = arm(s, amp1, (a) => a.copyWith(bootDeadline: ms(0) + kBootTimeout));
      s = s.tick(ms(0) + kBootTimeout);
      expect(deriveControlView(s).power, PowerPhase.off);
    });

    test('confirmed channel mirrors the raw report, never a pending value', () {
      var s = AmpState.initial.ingest(reportFrom(amp1, volumeDb: -25), ms(0));
      s = arm(s, amp1, (a) => a.copyWith(pendingVolumeDb: PendingValue(-20.0, ms(400))));
      final c = deriveConfirmed(s)!;
      expect(c.volumeDb, -25.0);
      expect(c.volumeRaw, 145);
      expect(c.receivedAt, ms(0));
      expect(deriveControlView(s).volumeDb, -20.0);
      expect(deriveConfirmed(AmpState.initial), isNull);
    });
  });

  group('staleness (8 s on a monotonic clock)', () {
    test('7999 ms after the last broadcast is connected, 8000 ms is not, next broadcast reconnects', () {
      var s = AmpState.initial.ingest(reportFrom(amp1), ms(0)).copyWith(selectedIp: amp1, hasExplicitSelection: true);
      expect(deriveControlView(s.tick(ms(7999))).hasAmp, isTrue);
      s = s.tick(ms(8000));
      final silent = deriveControlView(s);
      expect(silent.hasAmp, isFalse);
      expect(silent.selectedAmp, isNull);
      expect(silent.knownAmps, isEmpty);
      expect(silent.selectedIp, amp1, reason: 'the choice survives silence');
      expect(s.hasExplicitSelection, isTrue);
      s = s.ingest(reportFrom(amp1), ms(9000));
      expect(deriveControlView(s).hasAmp, isTrue, reason: 'reconnects without a tap');
    });
  });

  group('selection', () {
    test('auto-select-if-alone only when never chosen and exactly one amp is known', () {
      final one = AmpState.initial.ingest(reportFrom(amp1), ms(0));
      expect(one.effectiveIp, amp1);
      final two = one.ingest(reportFrom(amp2), ms(0));
      expect(two.effectiveIp, isNull);
      expect(deriveControlView(two).hasAmp, isFalse);
      expect(deriveControlView(two).knownAmps.length, 2);
    });

    test('explicit None never auto-selects, even when alone', () {
      final s = AmpState.initial
          .copyWith(selectedIp: null, hasExplicitSelection: true)
          .ingest(reportFrom(amp1), ms(0));
      expect(s.effectiveIp, isNull);
      expect(deriveControlView(s).hasAmp, isFalse);
    });

    test('a never-heard manual IP is a valid selection, not connected until heard', () {
      var s = AmpState.initial.copyWith(selectedIp: '192.0.2.99', hasExplicitSelection: true);
      expect(deriveControlView(s).hasAmp, isFalse);
      expect(deriveControlView(s).selectedIp, '192.0.2.99');
      s = s.ingest(reportFrom('192.0.2.99'), ms(0));
      expect(deriveControlView(s).hasAmp, isTrue);
    });

    test('only the selected amp\'s broadcast touches control state; every broadcast feeds the list', () {
      var s = AmpState.initial.ingest(reportFrom(amp1, volumeDb: -25), ms(0)).copyWith(selectedIp: amp1, hasExplicitSelection: true);
      s = s.ingest(reportFrom(amp2, volumeDb: -10, muted: true, power: false), ms(100));
      final v = deriveControlView(s);
      expect(v.volumeDb, -25.0);
      expect(v.isMuted, isFalse);
      expect(v.power, PowerPhase.on);
      expect(v.knownAmps.map((a) => a.ip), [amp1, amp2]);
    });
  });

  group('pending-command mask (3.1.0 / 3.1.1)', () {
    late AmpState s0;
    setUp(() {
      s0 = AmpState.initial.ingest(reportFrom(amp1, volumeDb: -25), ms(0)).copyWith(selectedIp: amp1, hasExplicitSelection: true);
    });

    AmpState setVolume(AmpState s, double db, Duration now) =>
        arm(s, amp1, (a) => a.copyWith(pendingVolumeDb: PendingValue(db, now + kPendingWindow)));

    test('gotcha #1/#2: a late pre-change broadcast does not overwrite the just-set value', () {
      var s = setVolume(s0, -24, ms(0));
      s = s.ingest(reportFrom(amp1, volumeDb: -25), ms(100)); // authored before our command landed
      expect(deriveControlView(s).volumeDb, -24.0);
      expect(deriveConfirmed(s)!.volumeDb, -25.0, reason: 'confirmed channel stays unmasked');
      s = s.ingest(reportFrom(amp1, volumeDb: -24), ms(200)); // the amp confirms
      expect(s.amps[amp1]!.pendingVolumeDb, isNull);
      expect(deriveControlView(s).volumeDb, -24.0);
      expect(deriveConfirmed(s)!.volumeDb, -24.0);
    });

    test('proof the assertion catches the bug: the same sequence applied unmasked shows the stale value', () {
      var s = setVolume(s0, -24, ms(0));
      s = applyUnmasked(s, reportFrom(amp1, volumeDb: -25), ms(100));
      expect(deriveControlView(s).volumeDb, -25.0, reason: 'this is exactly the jump the masked test forbids');
    });

    test('no confirmation: falls back to the amp\'s value when the deadline passes (>= 400 ms)', () {
      var s = setVolume(s0, -24, ms(0));
      s = s.tick(ms(399));
      expect(deriveControlView(s).volumeDb, -24.0);
      s = s.tick(ms(400));
      expect(deriveControlView(s).volumeDb, -25.0);
    });

    test('a newer command replaces the value and re-arms the deadline', () {
      var s = setVolume(s0, -24, ms(0));
      s = setVolume(s, -23, ms(300));
      s = s.ingest(reportFrom(amp1, volumeDb: -25), ms(500));
      expect(deriveControlView(s).volumeDb, -23.0, reason: 'inside the re-armed window');
      s = s.tick(ms(700));
      expect(deriveControlView(s).volumeDb, -25.0);
    });

    test('rapid steps accumulate on the displayed (pending) value', () {
      var s = s0;
      for (var i = 1; i <= 5; i++) {
        final base = s.amps[amp1]!.displayedVolumeDb;
        s = setVolume(s, base + 1, ms(10 * i));
      }
      expect(deriveControlView(s).volumeDb, -20.0);
    });

    test('mute, power and source are masked the same way', () {
      var s = arm(s0, amp1, (a) => a.copyWith(
        pendingMuted: PendingValue(true, ms(400)),
        pendingPower: PendingValue(false, ms(400)),
        pendingSource: PendingValue(3, ms(400)),
      ));
      s = s.ingest(reportFrom(amp1, muted: false, power: true, active: 0), ms(100));
      var v = deriveControlView(s);
      expect((v.isMuted, v.power, v.activeSourceIndex), (true, PowerPhase.off, 3));
      s = s.ingest(reportFrom(amp1, muted: true, power: false, active: 3), ms(200));
      final a = s.amps[amp1]!;
      expect([a.pendingMuted, a.pendingPower, a.pendingSource], everyElement(isNull));
      v = deriveControlView(s);
      expect((v.isMuted, v.power, v.activeSourceIndex), (true, PowerPhase.off, 3));
    });

    test('a broadcast carries an armed mask forward instead of wiping it', () {
      var s = setVolume(s0, -24, ms(0));
      s = s.ingest(reportFrom(amp1, volumeDb: -25), ms(50));
      expect(s.amps[amp1]!.pendingVolumeDb, const PendingValue(-24.0, Duration(milliseconds: 400)));
    });
  });

  group('ControlViewState equality', () {
    test('identical derivations are equal so the view provider does not rebuild', () {
      final s = AmpState.initial.ingest(reportFrom(amp1), ms(0));
      expect(deriveControlView(s), deriveControlView(s.ingest(reportFrom(amp1), ms(200))));
      expect(deriveControlView(s), isNot(deriveControlView(s.ingest(reportFrom(amp1, volumeDb: -24), ms(200)))));
    });
  });
}
