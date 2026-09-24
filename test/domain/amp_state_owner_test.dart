import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/domain/amp_command_sink.dart';
import 'package:devialet_expert_remote_app/domain/amp_state_owner.dart';
import 'package:devialet_expert_remote_app/domain/amp_trace.dart';
import 'package:devialet_expert_remote_app/domain/amp_tracker.dart';
import 'package:devialet_expert_remote_app/domain/control_view_state.dart';
import 'package:devialet_expert_remote_app/domain/debug/synthetic_status.dart';
import 'package:devialet_expert_remote_app/domain/devialet_client_provider.dart';
import 'package:devialet_expert_remote_app/domain/monotonic_clock.dart';
import 'package:devialet_expert_remote_app/domain/settings/app_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/hydrated_settings.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_owner.dart';
import 'package:devialet_expert_remote_app/domain/settings/settings_store.dart';
import 'package:devialet_expert_remote_app/networking/devialet_client.dart';
import 'package:devialet_expert_remote_app/networking/status_packet_builder.dart';

import '../networking/fake_udp_transport.dart';
import 'support/fake_time.dart';
import 'support/settings_support.dart';

class ThrowingCommandSink implements AmpCommandSink {
  @override
  Future<void> setVolumeDb(String ip, double db) async => throw StateError('no route to host');
  @override
  Future<void> setMute(String ip, bool muted) async => throw StateError('no route to host');
  @override
  Future<void> setPower(String ip, bool on) async => throw StateError('no route to host');
  @override
  Future<void> selectSource(String ip, int statusIndex, {required double postSwitchDb}) async =>
      throw StateError('no route to host');
  @override
  Future<void> sendStartupVolume(String ip, double db) async => throw StateError('no route to host');
}

/// The Android-era bug: only the ip is persisted, so "chose None" and
/// "never chose" collapse into one state.
class _DroppingFlagStore extends InMemorySettingsStore {
  @override
  Future<void> write(String key, Object? value) async {
    if (key == SettingsKeys.hasExplicitSelection) return;
    await super.write(key, value);
  }
}

class RecordingCommandSink extends NoopCommandSink {
  RecordingCommandSink({this.clock, this.failStartup = false, this.failMute = false, this.failSource = false});

  final FakeClock? clock;
  final bool failStartup;
  final bool failMute;
  final bool failSource;
  final List<String> calls = [];
  final List<Duration> startupSentAt = [];

  @override
  Future<void> setVolumeDb(String ip, double db) async => calls.add('volume $ip $db');
  @override
  Future<void> setMute(String ip, bool muted) async {
    calls.add('mute $ip $muted');
    if (failMute) throw StateError('no route to host');
  }
  @override
  Future<void> setPower(String ip, bool on) async => calls.add('power $ip $on');
  @override
  Future<void> selectSource(String ip, int statusIndex, {required double postSwitchDb}) async {
    calls.add('source $ip $statusIndex $postSwitchDb');
    if (failSource) throw StateError('no route to host');
  }
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

  late InMemorySettingsStore settingsStore;

  /// Captured `[amp]` trace lines when [make] is called with `traced: true`.
  late List<String> traceLines;

  ProviderContainer make({
    AmpCommandSink sink = const NoopCommandSink(),
    InMemorySettingsStore? store,
    AppSettings? initialSettings,
    bool traced = false,
  }) {
    clock = FakeClock();
    ticker = ManualTicker();
    transport = FakeUdpTransport();
    settingsStore = store ?? InMemorySettingsStore();
    traceLines = [];
    addTearDown(ticker.close);
    return ProviderContainer.test(
      overrides: [
        devialetTransportProvider.overrideWithValue(transport),
        monotonicClockProvider.overrideWithValue(clock),
        staleTickProvider.overrideWithValue(ticker.stream),
        ampCommandSinkProvider.overrideWithValue(sink),
        hydratedSettingsProvider.overrideWithValue(testHydrated(store: settingsStore, initial: initialSettings)),
        if (traced) ampTraceProvider.overrideWithValue(AmpTrace(traceLines.add, clock)),
      ],
    );
  }

  /// Trace lines with the `[amp] <ms>ms ` prefix stripped.
  List<String> events() => [for (final l in traceLines) l.replaceFirst(RegExp(r'^\[amp\] \d+ms '), '')];

  /// "Kill and relaunch": a fresh container hydrated from the same store,
  /// exactly as main() would do it.
  Future<ProviderContainer> relaunch(InMemorySettingsStore store) async =>
      make(store: store, initialSettings: AppSettings.load(await store.loadAll()).settings);

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

  test('five rapid steps accumulate on the displayed value (the fixture step is 0.5 dB)', () async {
    final c = make();
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
    for (var i = 0; i < 5; i++) {
      owner(c).stepVolume(1);
    }
    expect(view(c).volumeDb, -22.5);
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

  test('selectSource accepts enabled slots only: a disabled slot sends nothing, an enabled one sends once', () async {
    final sink = RecordingCommandSink();
    final c = make(sink: sink);
    seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
    await owner(c).selectSource(9);
    expect(view(c).activeSourceIndex, 0);
    expect(sink.calls, isEmpty);
    await owner(c).selectSource(3);
    expect(view(c).activeSourceIndex, 3);
    expect(sink.calls, ['source 192.0.2.22 3 -40.0']);
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

    AmpStatusReport on({double volumeDb = -25}) =>
        syntheticReport(ip: ip, name: 'My Devialet', isPoweredOn: true, volumeDb: volumeDb);
    AmpStatusReport off({double volumeDb = -25}) =>
        syntheticReport(ip: ip, name: 'My Devialet', isPoweredOn: false, volumeDb: volumeDb);

    /// Seeds the Off shape and taps power: a self-initiated boot at t = 0.
    Future<RecordingCommandSink> bootFromOff(ProviderContainer c, RecordingCommandSink sink) async {
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
      await owner(c).togglePower();
      return sink;
    }

    test('an external power-on (widget, remote, front panel) on the selected amp gets the hold and the startup send (3.2.5)', () async {
      final sink = RecordingCommandSink(clock: clock);
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off).copyWith(volumeDb: -40));
      clock.set(s(1));
      owner(c).ingest(on(volumeDb: -40)); // first On packet: pre-shutdown byte == target
      expect(view(c).power, PowerPhase.on, reason: 'no Booting for a boot we did not start');
      expect(view(c).volumeDb, -40.0);
      clock.set(s(1, 200));
      owner(c).ingest(on(volumeDb: -42));
      expect(view(c).volumeDb, -40.0, reason: 'the misreport is held');
      expect(sink.calls, isEmpty, reason: 'nothing before +500 ms');
      clock.set(s(1, 600));
      owner(c).ingest(on(volumeDb: -42));
      await settle();
      expect(sink.calls, ['startup $ip -40.0']);
      clock.set(s(1, 800));
      owner(c).ingest(on(volumeDb: -40));
      expect(c.read(ampStateProvider).amps[ip]!.pendingVolumeDb, isNull, reason: 'released by the real confirmation');
      expect(view(c).volumeDb, -40.0);
    });

    test('an external power-on on a non-selected amp gets nothing', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
      const other = '192.0.2.23';
      owner(c).ingest(syntheticReport(ip: other, name: 'other', isPoweredOn: false));
      clock.set(s(1));
      owner(c).ingest(syntheticReport(ip: other, name: 'other', isPoweredOn: true, volumeDb: -42));
      clock.set(s(1, 600));
      owner(c).ingest(syntheticReport(ip: other, name: 'other', isPoweredOn: true, volumeDb: -42));
      await settle();
      expect(c.read(ampStateProvider).amps[other]!.boot, isNull);
      expect(sink.calls, isEmpty);
    });

    test(
      'self-initiated: one power send, Booting through Off broadcasts, repeat taps send nothing and do not extend',
      () async {
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
        expect(
          view(c).power,
          PowerPhase.off,
          reason: 'silent fallback at the 20 s deadline, not extended by the second tap',
        );
        expect(view(c).hasAmp, isTrue);
      },
    );

    test(
      'a late On after the timeout is plain On (no Booting) but still gets the follow-ups as an observed boot',
      () async {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        await bootFromOff(c, sink);
        clock.set(s(20));
        owner(c).ingest(off());
        expect(view(c).power, PowerPhase.off, reason: 'silent fallback at the deadline');
        clock.set(s(25));
        owner(c).ingest(on(volumeDb: -42));
        expect(view(c).power, PowerPhase.on);
        expect(view(c).volumeDb, -40.0, reason: 'held at the target');
        clock.set(s(25, 600));
        owner(c).ingest(on(volumeDb: -42));
        await settle();
        expect(sink.calls, ['power $ip true', 'startup $ip -40.0']);
      },
    );

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

    test('regression (S25 2026-09-20): powered off at the target, no −42 flash through the whole boot', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off).copyWith(volumeDb: -40));
      await owner(c).togglePower();
      final shown = <double>[];
      clock.set(s(16));
      owner(c).ingest(on(volumeDb: -40)); // pre-shutdown byte == target
      shown.add(view(c).volumeDb);
      for (final t in [200, 400, 600]) {
        clock.set(s(16, t));
        owner(c).ingest(on(volumeDb: -42));
        await settle();
        shown.add(view(c).volumeDb);
      }
      clock.set(s(16, 800));
      owner(c).ingest(on(volumeDb: -40)); // the amp applied the startup send
      shown.add(view(c).volumeDb);
      expect(shown, everyElement(-40.0), reason: 'never −42');
      expect(sink.calls.where((x) => x.startsWith('startup')), ['startup $ip -40.0']);
      expect(c.read(ampStateProvider).amps[ip]!.pendingVolumeDb, isNull, reason: 'released by the real confirmation');
    });

    test('the hold releases on a confirming push, or at 1500 ms after the send via tick', () async {
      for (final viaTick in [false, true]) {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        await bootFromOff(c, sink);
        clock.set(s(16));
        owner(c).ingest(on());
        clock.set(s(16, 200));
        owner(c).ingest(on(volumeDb: -42));
        if (!viaTick) {
          clock.set(s(16, 600));
          owner(c).ingest(on(volumeDb: -42)); // the send goes out on this ingest
          await settle();
          clock.set(s(16, 800));
          owner(c).ingest(on(volumeDb: -40)); // the amp applied it
          expect(c.read(ampStateProvider).amps[ip]!.pendingVolumeDb, isNull);
          clock.set(s(17));
          owner(c).ingest(on(volumeDb: -41));
          expect(view(c).volumeDb, -41.0);
        } else {
          // The send went out at +600 ms; the fallback runs 1500 ms from it.
          clock.set(s(16, 600));
          owner(c).ingest(on(volumeDb: -42));
          await settle();
          clock.set(s(18, 99));
          ticker.tick();
          await settle();
          expect(view(c).volumeDb, -40.0);
          clock.set(s(18, 100));
          ticker.tick();
          await settle();
          expect(view(c).volumeDb, -42.0, reason: 'bounded hold: the misreport shows honestly');
        }
      }
    });

    group('debug trace (Task 3.5.2)', () {
      const ipField = 'ip=$ip';

      test('narrates a self-initiated boot in order; the held −42 never reaches the view', () async {
        final sink = RecordingCommandSink(clock: clock);
        final c = make(sink: sink, traced: true);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
        traceLines.clear();
        await owner(c).togglePower();
        clock.set(s(16));
        owner(c).ingest(on(volumeDb: -25)); // first On packet: pre-shutdown byte
        clock.set(s(16, 200));
        owner(c).ingest(on(volumeDb: -42)); // the misreport
        clock.set(s(16, 400));
        owner(c).ingest(on(volumeDb: -42)); // unchanged: no rx line
        clock.set(s(16, 600));
        owner(c).ingest(on(volumeDb: -42)); // the send goes out
        await settle();
        clock.set(s(16, 800));
        owner(c).ingest(on(volumeDb: -40)); // the amp applied it
        expect(events(), [
          'boot booting $ipField deadlineMs=20000 target=-40.0',
          'view power=booting db=-25.0 muted=false hasAmp=true source=0',
          'rx $ipField power=on raw=145 db=-25.0 source=0',
          'boot confirmed $ipField target=-40.0 sendAtMs=500 holdUntilMs=1500',
          'view power=on db=-40.0 muted=false hasAmp=true source=0',
          'rx $ipField power=on raw=111 db=-42.0 source=0',
          'boot startup-send $ipField target=-40.0 sinceOnMs=600',
          'rx $ipField power=on raw=115 db=-40.0 source=0',
          'hold released $ipField reason=confirmed sinceOnMs=800 raw=115 db=-40.0',
        ]);
        expect(traceLines[2], startsWith('[amp] 16000ms '));
        expect(
          traceLines.where((l) => l.contains('view') && l.contains('db=-42.0')),
          isEmpty,
          reason: 'the hold keeps the misreport off the display (its counter-test is applyUnheld)',
        );
      });

      test('a fallback release via the tick says so, and the view then shows the misreport', () async {
        final sink = RecordingCommandSink();
        final c = make(sink: sink, traced: true);
        await bootFromOff(c, sink);
        clock.set(s(16));
        owner(c).ingest(on());
        clock.set(s(16, 600));
        owner(c).ingest(on(volumeDb: -42));
        await settle();
        traceLines.clear();
        clock.set(s(18, 100));
        ticker.tick();
        await settle();
        expect(events(), [
          'hold released $ipField reason=fallback sinceOnMs=2100 raw=111 db=-42.0',
          'view power=on db=-42.0 muted=false hasAmp=true source=0',
        ]);
      });

      test('an observed external boot and a boot timeout are named', () async {
        final sink = RecordingCommandSink();
        final c = make(sink: sink, traced: true);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
        traceLines.clear();
        clock.set(s(1));
        owner(c).ingest(on(volumeDb: -42));
        expect(events().where((e) => e.startsWith('boot')), ['boot observed-external $ipField target=-40.0']);

        final c2 = make(sink: RecordingCommandSink(), traced: true);
        await bootFromOff(c2, sink);
        traceLines.clear();
        clock.set(s(20));
        owner(c2).ingest(off());
        expect(events(), ['boot timeout $ipField', 'view power=off db=-25.0 muted=false hasAmp=true source=0']);
      });

      test('a throwing sink is reported as a failed send, then the rollback shows in the view', () async {
        final c = make(sink: ThrowingCommandSink(), traced: true);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
        traceLines.clear();
        await owner(c).toggleMute();
        expect(events(), [
          'view power=on db=-25.0 muted=true hasAmp=true source=0',
          'send failed $ipField error=Bad state: no route to host',
          'view power=on db=-25.0 muted=false hasAmp=true source=0',
        ]);
      });

      test('untraced by default: the same boot produces no lines', () async {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        await bootFromOff(c, sink);
        clock.set(s(16));
        owner(c).ingest(on());
        expect(traceLines, isEmpty);
      });
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

  group('persisted settings (3.3.x / 3.9.1)', () {
    const a = '192.0.2.22';
    const b = '192.0.2.23';
    Future<void> settle() => Future<void>.delayed(Duration.zero);
    AmpStatusReport from(String ip) => syntheticReport(ip: ip, name: 'Amp $ip');

    test('the owner starts from the persisted selection, range and startup volume', () {
      final c = make(
        initialSettings: AppSettings.defaults.copyWith(
          selectedIp: a,
          hasExplicitSelection: true,
          floorDb: -60,
          ceilingDb: -20,
          startupVolumeDb: -30,
        ),
      );
      final s = c.read(ampStateProvider);
      expect((s.selectedIp, s.hasExplicitSelection), (a, true));
      expect((s.floorDb, s.ceilingDb, s.startupVolumeTarget), (-60.0, -20.0, -30.0));
      expect(view(c).selectedIp, a);
    });

    test('limit and startup changes on the settings owner reach the amp owner synchronously', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
      c.read(settingsProvider.notifier).setVolumeLimits(floorDb: -70, ceilingDb: -20);
      expect((view(c).floorDb, view(c).ceilingDb), (-70.0, -20.0));
      c.read(settingsProvider.notifier).setStartupVolumeDb(-30);
      await owner(c).togglePower();
      clock.set(const Duration(seconds: 16));
      owner(c).ingest(syntheticReport(ip: a, name: 'a', isPoweredOn: true));
      expect(view(c).volumeDb, -30.0, reason: 'the hold uses the new startup value');
      clock.set(const Duration(seconds: 16, milliseconds: 600));
      owner(c).ingest(syntheticReport(ip: a, name: 'a', isPoweredOn: true, volumeDb: -42));
      await settle();
      expect(sink.calls.last, 'startup $a -30.0');
    });

    test('restart: a chosen amp reconnects after its first broadcast with no tap (3.0.8 end to end)', () async {
      final c1 = make();
      owner(c1).ingest(from(a));
      owner(c1).ingest(from(b));
      owner(c1).selectIp(b);
      await settle();
      final c2 = await relaunch(settingsStore);
      expect(view(c2).hasAmp, isFalse);
      expect(view(c2).selectedIp, b);
      owner(c2).ingest(from(b));
      expect(view(c2).selectedAmp?.ip, b);
    });

    test('restart: "chose None" is not resurrected by auto-select; "never chose" still auto-selects', () async {
      final c1 = make();
      owner(c1).ingest(from(a));
      owner(c1).selectIp(null);
      await settle();
      final c2 = await relaunch(settingsStore);
      owner(c2).ingest(from(a));
      expect(view(c2).hasAmp, isFalse, reason: 'the user opted out; one lone amp must not be re-picked');

      final fresh = make();
      owner(fresh).ingest(from(a));
      expect(view(fresh).hasAmp, isTrue, reason: 'never chosen + exactly one amp → auto-select');
    });

    test('restart: range and startup come back', () async {
      final c1 = make();
      c1.read(settingsProvider.notifier).setVolumeLimits(floorDb: -70, ceilingDb: -20);
      c1.read(settingsProvider.notifier).setStartupVolumeDb(-30);
      await settle();
      final c2 = await relaunch(settingsStore);
      final s = c2.read(ampStateProvider);
      expect((s.floorDb, s.ceilingDb, s.startupVolumeDb), (-70.0, -20.0, -30.0));
    });

    test('seeding and the debug seams never write to the store (checklist 19)', () async {
      final c = make();
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
      owner(c).seedSelection(a);
      owner(c).setVolumeRange(floorDb: -70);
      await settle();
      expect(settingsStore.writeLog, isEmpty);
    });

    test('proof the seam split is load-bearing: the user intent does persist the address', () async {
      final c = make();
      owner(c).selectIp(a);
      await settle();
      expect(settingsStore.values[SettingsKeys.selectedIp], a);
    });

    test('proof the flag protects "chose None": a store that drops it lets auto-select resurrect the amp', () async {
      final dropping = _DroppingFlagStore();
      final c1 = make(store: dropping);
      owner(c1).ingest(from(a));
      owner(c1).selectIp(null);
      await settle();
      final c2 = await relaunch(dropping);
      owner(c2).ingest(from(a));
      expect(view(c2).hasAmp, isTrue, reason: 'exactly the resurrection the flag prevents');
    });

    test('proof the heal is what catches an inverted pair', () async {
      final raw = {SettingsKeys.volumeFloorDb: -10.0, SettingsKeys.volumeCeilingDb: -50.0};
      final healed = make(initialSettings: AppSettings.load(raw).settings);
      expect((view(healed).floorDb, view(healed).ceilingDb), (-40.0, -39.0));
      // The same raw pair bound without healing leaks straight into the view.
      final unhealed = make(initialSettings: AppSettings.defaults.copyWith(floorDb: -10, ceilingDb: -50));
      expect((view(unhealed).floorDb, view(unhealed).ceilingDb), (-10.0, -50.0));
    });
  });

  group('volume wiring (3.6.x) and mute (3.7.x)', () {
    const ip = '192.0.2.22';
    Duration s(int seconds, [int ms = 0]) => Duration(seconds: seconds, milliseconds: ms);
    AmpStatusReport on({double volumeDb = -25, bool muted = false}) =>
        syntheticReport(ip: ip, name: 'My Devialet', isPoweredOn: true, volumeDb: volumeDb, isMuted: muted);
    SettingsNotifier settings(ProviderContainer c) => c.read(settingsProvider.notifier);
    Iterable<String> mutes(RecordingCommandSink sink) => sink.calls.where((x) => x.startsWith('mute'));
    Iterable<String> volumes(RecordingCommandSink sink) => sink.calls.where((x) => x.startsWith('volume'));

    test('one step = the configured size; a settings change applies to the next step (3.6.0)', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected)); // fixture step 0.5
      expect(view(c).stepDb, 0.5);
      expect(owner(c).stepVolume(1), isTrue);
      expect(view(c).volumeDb, -24.5);
      settings(c).setStepDb(VolumeStepDb.two);
      expect(view(c).stepDb, 2.0);
      owner(c).stepVolume(1);
      expect(view(c).volumeDb, -22.5);
      settings(c).setStepDb(VolumeStepDb.one);
      owner(c).stepVolume(-1);
      expect(view(c).volumeDb, -23.5);
      await settle();
      expect(volumes(sink), ['volume $ip -24.5', 'volume $ip -22.5', 'volume $ip -23.5']);
    });

    test('every step path clamps on the already-clamped value: a bound step reports false and sends nothing (3.6.2)', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.connectedFixture.copyWith(volumeDb: -15.5));
      expect(owner(c).stepVolume(1), isTrue, reason: 'half a step to the ceiling');
      expect(view(c).volumeDb, -15.0);
      expect(owner(c).stepVolume(1), isFalse);
      expect(owner(c).stepVolume(1), isFalse, reason: 'idempotent: clamp(clamp(x)) == clamp(x)');
      await settle();
      expect(volumes(sink), ['volume $ip -15.0'], reason: 'nothing re-sent at the bound');
      await owner(c).setVolumeDb(5);
      expect(view(c).volumeDb, -15.0);
      expect(volumes(sink).last, 'volume $ip -15.0', reason: 'an absolute value is clamped through the same function');
    });

    test('a user volume change on a muted amp unmutes first, then sends the volume; the view unmutes at once (3.6.5)', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.muted));
      expect(view(c).isMuted, isTrue);
      owner(c).stepVolume(1);
      expect((view(c).isMuted, view(c).volumeDb), (false, -24.5), reason: 'both written before any send');
      await settle();
      expect(sink.calls, ['mute $ip false', 'volume $ip -24.5'], reason: 'KDE order: mute off, then volume');
    });

    test('the dial release goes through the same unmute path (checklist 6: every input path)', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.muted));
      await owner(c).setVolumeDb(-30);
      expect(sink.calls, ['mute $ip false', 'volume $ip -30.0']);
      expect(view(c).isMuted, isFalse);
    });

    test('ten repeat ticks on a muted amp send exactly one mute-off; a bound press on a muted amp still unmutes', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.muted));
      for (var i = 0; i < 10; i++) {
        expect(owner(c).stepVolume(1), isTrue);
      }
      await settle();
      expect(mutes(sink).length, 1, reason: 'the optimistic unmute masks displayedMuted for the rest');
      expect(volumes(sink).length, 10);
      expect(view(c).volumeDb, -20.0);

      final sink2 = RecordingCommandSink();
      final c2 = make(sink: sink2);
      seedFromControlView(owner(c2), ControlViewState.forScenario(DebugScenario.muted).copyWith(volumeDb: -15));
      expect(owner(c2).stepVolume(1), isTrue, reason: 'at the ceiling but muted: the press unmutes and re-asserts');
      expect(owner(c2).stepVolume(1), isFalse, reason: 'now unmuted at the ceiling: nothing to do');
      await settle();
      expect(sink2.calls, ['mute $ip false', 'volume $ip -15.0']);
    });

    test('once the 400 ms mask expires with the amp still muted, the next user change re-sends mute-off', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.muted));
      owner(c).stepVolume(1);
      await settle();
      clock.advance(const Duration(milliseconds: 400));
      owner(c).ingest(on(volumeDb: -24.5, muted: true)); // the amp ignored the unmute
      expect(view(c).isMuted, isTrue, reason: 'the mask expired; the amp says muted');
      owner(c).stepVolume(1);
      await settle();
      expect(mutes(sink), ['mute $ip false', 'mute $ip false'], reason: 'the gesture retries the dropped unmute');
    });

    test('a failed unmute rolls back only the mute slot; the volume still goes out and stays', () async {
      final sink = RecordingCommandSink(failMute: true);
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.muted));
      await owner(c).setVolumeDb(-30);
      expect(sink.calls, ['mute $ip false', 'volume $ip -30.0']);
      expect((view(c).isMuted, view(c).volumeDb), (true, -30.0));
    });

    test('corrections never unmute (3.7.1): the startup send and the limit clamp leave a muted amp muted', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off).copyWith(isMuted: true));
      await owner(c).togglePower();
      clock.set(s(16));
      owner(c).ingest(on(muted: true));
      clock.set(s(16, 600));
      owner(c).ingest(on(volumeDb: -42, muted: true));
      await settle();
      clock.set(s(16, 800));
      owner(c).ingest(on(volumeDb: -40, muted: true));
      clock.set(s(18));
      ticker.tick();
      await settle();
      expect(sink.calls, ['power $ip true', 'startup $ip -40.0']);
      expect(view(c).isMuted, isTrue);
      // Now the clamp, on the same muted amp.
      settings(c).setVolumeLimits(ceilingDb: -45);
      await settle();
      expect(sink.calls.last, 'volume $ip -45.0');
      expect(mutes(sink), isEmpty, reason: 'counter-half of 3.6.5: a correction is not a user gesture');
      expect((view(c).isMuted, view(c).volumeDb), (true, -45.0));
    });

    group('limit-change clamp (3.6.6 / 3.4.13)', () {
      test('a ceiling below the displayed value sends one clamp and the view moves at once; a floor above it clamps up', () async {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected)); // −25 in −60..−15
        settings(c).setVolumeLimits(ceilingDb: -30);
        await settle();
        expect(sink.calls, ['volume $ip -30.0']);
        expect(view(c).volumeDb, -30.0);
        settings(c).setVolumeLimits(ceilingDb: -15); // widen back: in range, nothing sent
        settings(c).setVolumeLimits(floorDb: -28);
        await settle();
        expect(sink.calls, ['volume $ip -30.0', 'volume $ip -28.0']);
        expect(view(c).volumeDb, -28.0);
      });

      test('nothing is sent when the displayed value is already in range', () async {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
        settings(c).setVolumeLimits(floorDb: -55, ceilingDb: -16);
        settings(c).setVolumeLimits(floorDb: -26);
        await settle();
        expect(sink.calls, isEmpty);
        expect(view(c).volumeDb, -25.0);
      });

      test('several triggers in one synchronous run coalesce into exactly one command, at the final limits', () async {
        // Counter-run (checklist 20), by hand: with `_scheduleLimitClamp`
        // calling `_applyLimitClamp` directly instead of a microtask, this
        // records two commands (−30.0 then −35.0).
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
        settings(c).setVolumeLimits(ceilingDb: -30);
        settings(c).setVolumeLimits(ceilingDb: -35);
        owner(c).setVolumeRange(floorDb: -50);
        await settle();
        expect(sink.calls, ['volume $ip -35.0']);
      });

      test('an amp that is Off gets nothing; power reaching On through a boot leaves it in range by construction', () async {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off)); // −25 shown, Off
        settings(c).setVolumeLimits(ceilingDb: -30);
        await settle();
        expect(sink.calls, isEmpty, reason: 'the amp drops commands while Off');
        await owner(c).togglePower();
        clock.set(s(16));
        owner(c).ingest(on(volumeDb: -25));
        clock.set(s(16, 600));
        owner(c).ingest(on(volumeDb: -42));
        await settle();
        clock.set(s(16, 800));
        owner(c).ingest(on(volumeDb: -40));
        clock.set(s(18));
        ticker.tick(); // the boot record drops: the clamp evaluates and finds −40 in range
        await settle();
        expect(sink.calls, ['power $ip true', 'startup $ip -40.0']);
        expect(view(c).volumeDb, -40.0);
      });

      test('limits narrowed during a boot: the startup send is clamped to the limits in force, so no second command', () async {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
        await owner(c).togglePower();
        clock.set(s(5));
        settings(c).setVolumeLimits(ceilingDb: -45); // mid-boot; the record's target was −40
        clock.set(s(16));
        owner(c).ingest(on(volumeDb: -25));
        expect(view(c).volumeDb, -40.0, reason: 'the hold arms with the record target');
        clock.set(s(16, 600));
        owner(c).ingest(on(volumeDb: -42));
        await settle();
        expect(sink.calls, ['power $ip true', 'startup $ip -45.0']);
        expect(view(c).volumeDb, -45.0, reason: 'the hold re-arms on the clamped send');
        clock.set(s(16, 800));
        owner(c).ingest(on(volumeDb: -45));
        clock.set(s(18));
        ticker.tick();
        await settle();
        expect(sink.calls.length, 2, reason: 'the post-boot evaluation is a no-op');
      });

      test('a failed startup send drops the record through the rollback, which still triggers the clamp', () async {
        final sink = RecordingCommandSink(failStartup: true);
        final c = make(sink: sink);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
        await owner(c).togglePower();
        settings(c).setVolumeLimits(ceilingDb: -45);
        clock.set(s(16));
        owner(c).ingest(on(volumeDb: -25));
        clock.set(s(16, 600));
        owner(c).ingest(on(volumeDb: -42));
        await settle();
        expect(sink.calls, ['power $ip true', 'startup $ip -45.0', 'volume $ip -45.0']);
        expect(view(c).volumeDb, -45.0, reason: 'the −42 the amp reports is above the new ceiling');
      });

      test('connection landing and a selection change each clamp the amp that became current; others are untouched', () async {
        const b = '192.0.2.23';
        final sink = RecordingCommandSink();
        final c = make(
          sink: sink,
          initialSettings: AppSettings.defaults.copyWith(ceilingDb: -30, selectedIp: ip, hasExplicitSelection: true),
        );
        owner(c).ingest(on(volumeDb: -25));
        await settle();
        expect(sink.calls, ['volume $ip -30.0'], reason: 'landing out of range');
        expect(view(c).volumeDb, -30.0);
        owner(c).ingest(syntheticReport(ip: b, name: 'b', volumeDb: -20));
        await settle();
        expect(sink.calls.length, 1, reason: 'a non-selected amp is never corrected');
        owner(c).selectIp(b);
        await settle();
        expect(sink.calls, ['volume $ip -30.0', 'volume $b -30.0']);
        owner(c).selectIp(ip);
        await settle();
        expect(sink.calls.length, 2, reason: 'back to an amp already in range: nothing');
      });

      test('the clamp is one evaluation per trigger: an ignored clamp is not retried on a timer', () async {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
        settings(c).setVolumeLimits(ceilingDb: -30);
        await settle();
        for (var t = 200; t <= 3000; t += 200) {
          clock.advance(const Duration(milliseconds: 200));
          owner(c).ingest(on(volumeDb: -25)); // the amp keeps reporting the old value
          if (t % 1000 == 0) ticker.tick();
          await settle();
        }
        expect(sink.calls, ['volume $ip -30.0']);
        expect(view(c).volumeDb, -25.0, reason: 'after the mask, the amp\'s own (out-of-range) value shows honestly');
      });
    });

    test('3.6.4b: a user send inside the hold lets a matching push release it before the startup send, which still goes out with the user value', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
      await owner(c).togglePower();
      clock.set(s(16));
      owner(c).ingest(on(volumeDb: -25));
      clock.set(s(16, 300));
      await owner(c).setVolumeDb(-30);
      expect(sink.calls, ['power $ip true', 'volume $ip -30.0']);
      expect(c.read(ampStateProvider).amps[ip]!.boot!.userSent, isTrue);
      clock.set(s(16, 400));
      owner(c).ingest(on(volumeDb: -30));
      expect(c.read(ampStateProvider).amps[ip]!.pendingVolumeDb, isNull, reason: 'released by the user\'s own confirmation');
      expect(view(c).volumeDb, -30.0);
      clock.set(s(16, 600));
      owner(c).ingest(on(volumeDb: -30));
      await settle();
      expect(sink.calls.last, 'startup $ip -30.0', reason: 'the deferred send still carries the user value (deviation from KDE)');
      expect(view(c).volumeDb, -30.0);
    });
  });

  test('disposing the container stops listening and closes the transport', () async {
    final c = make();
    c.read(ampStateProvider);
    c.dispose();
    await settle();
    expect(transport.closed, isTrue);
  });

  group('source wiring (3.8.x)', () {
    const ip = '192.0.2.22';
    Duration s(int seconds, [int ms = 0]) => Duration(seconds: seconds, milliseconds: ms);
    AmpStatusReport on({double volumeDb = -25, bool muted = false, int source = 0}) => syntheticReport(
      ip: ip,
      name: 'My Devialet',
      isPoweredOn: true,
      volumeDb: volumeDb,
      isMuted: muted,
      activeSourceIndex: source,
    );
    SettingsNotifier settings(ProviderContainer c) => c.read(settingsProvider.notifier);
    TrackedAmp amp(ProviderContainer c) => c.read(ampStateProvider).amps[ip]!;

    test('one write arms source and volume together; one sink call carries the clamped startup target (3.8.0 / 3.8.1)', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected)); // −60..−15, at −25
      final pending = owner(c).selectSource(3);
      expect((view(c).activeSourceIndex, view(c).volumeDb), (3, -40.0), reason: 'both written before any send');
      expect(amp(c).pendingSource, PendingValue(3, const Duration(milliseconds: 400)));
      expect(amp(c).pendingVolumeDb, PendingValue(-40.0, const Duration(milliseconds: 400)));
      await pending;
      expect(sink.calls, ['source $ip 3 -40.0'], reason: 'source×2 then volume×2 happen inside this one call');
    });

    test('the forced volume is the startup setting clamped to the range in force', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
      settings(c).setVolumeLimits(ceilingDb: -45);
      await settle();
      sink.calls.clear();
      await owner(c).selectSource(3);
      expect(sink.calls, ['source $ip 3 -45.0']);
      expect(view(c).volumeDb, -45.0);
      settings(c).setStartupVolumeDb(-35);
      settings(c).setVolumeLimits(ceilingDb: -15);
      await settle();
      sink.calls.clear();
      await owner(c).selectSource(4);
      expect(sink.calls, ['source $ip 4 -35.0'], reason: 'the persisted startup setting, not a constant');
    });

    test('a source switch never touches mute (3.7.1): a muted amp stays muted and no mute is sent', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.muted));
      await owner(c).selectSource(3);
      expect(sink.calls, ['source $ip 3 -40.0']);
      expect(sink.calls.where((x) => x.startsWith('mute')), isEmpty, reason: 'counter-half of 3.6.5\'s auto-unmute');
      expect((view(c).isMuted, view(c).activeSourceIndex, view(c).volumeDb), (true, 3, -40.0));
      // The amp confirms with mute still on: the view stays muted.
      clock.set(s(0, 200));
      owner(c).ingest(on(volumeDb: -40, muted: true, source: 3));
      expect(view(c).isMuted, isTrue);
    });

    test('a switch is gated like every command: nothing while Off / Booting / no amp (checklist 6)', () async {
      for (final scenario in [DebugScenario.off, DebugScenario.booting, DebugScenario.notConnected]) {
        final sink = RecordingCommandSink();
        final c = make(sink: sink);
        seedFromControlView(owner(c), ControlViewState.forScenario(scenario));
        await owner(c).selectSource(3);
        expect(sink.calls, isEmpty, reason: scenario.name);
      }
    });

    test('gotcha #1/#2 at the owner: a late pre-change broadcast inside 400 ms does not overwrite the selection; the matching one confirms it', () async {
      final c = make(sink: RecordingCommandSink());
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
      await owner(c).selectSource(3);
      clock.set(s(0, 100));
      owner(c).ingest(on(source: 0)); // authored before our command landed
      expect(view(c).activeSourceIndex, 3);
      expect(c.read(confirmedAmpStateProvider)!.activeSourceIndex, 0, reason: 'confirmed channel stays unmasked');
      clock.set(s(0, 250));
      owner(c).ingest(on(source: 3, volumeDb: -40)); // the amp confirms
      expect(amp(c).pendingSource, isNull);
      expect(amp(c).pendingVolumeDb, isNull);
      expect(view(c).activeSourceIndex, 3);
      // Proof the assertion bites: with the mask expired the stale slot shows.
      final c2 = make(sink: RecordingCommandSink());
      seedFromControlView(owner(c2), ControlViewState.forScenario(DebugScenario.connected));
      await owner(c2).selectSource(3);
      clock.set(s(0, 400));
      owner(c2).ingest(on(source: 0));
      expect(view(c2).activeSourceIndex, 0, reason: 'the same broadcast lands once the window has closed');
    });

    test('a failed send rolls both slots back to their pre-arm values — a boot hold is restored, not dropped', () async {
      final sink = RecordingCommandSink(failSource: true);
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
      clock.set(s(1));
      owner(c).ingest(on(volumeDb: -25)); // observed external boot: hold armed at −40
      clock.set(s(1, 600));
      owner(c).ingest(on(volumeDb: -42)); // misreport; the startup send goes out (and succeeds)
      await settle();
      final hold = amp(c).pendingVolumeDb!;
      expect((hold.value, hold.deadline), (-40.0, s(3, 100)), reason: 'the hold runs 1500 ms from the send');
      clock.set(s(2));
      await owner(c).selectSource(3); // the switch throws
      expect(sink.calls.last, 'source $ip 3 -40.0');
      expect(amp(c).pendingSource, isNull, reason: 'rolled back');
      expect(amp(c).pendingVolumeDb, hold, reason: 'the hold survives the failed switch (rollback restores, never nulls)');
      expect(view(c).volumeDb, -40.0, reason: 'the −42 misreport stays off the display');
      expect(view(c).activeSourceIndex, 0);
    });

    test('a switch inside the post-boot hold keeps the hold\'s later deadline instead of the 400 ms window', () async {
      final sink = RecordingCommandSink();
      final c = make(sink: sink);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.off));
      clock.set(s(1));
      owner(c).ingest(on(volumeDb: -25)); // external boot observed: hold armed
      clock.set(s(1, 600));
      owner(c).ingest(on(volumeDb: -42)); // startup send at +600 → fallback at 3100
      await settle();
      expect(amp(c).pendingVolumeDb!.deadline, s(3, 100));
      clock.set(s(2));
      await owner(c).selectSource(3);
      expect(amp(c).pendingSource!.deadline, s(2, 400));
      expect(amp(c).pendingVolumeDb, PendingValue(-40.0, s(3, 100)), reason: 'never shortened to 2400');
      expect(amp(c).boot, isNotNull, reason: 'the boot record is untouched');
      expect(sink.calls.last, 'source $ip 3 -40.0');
    });

    test('a switch after the hold has released is a plain 400 ms mask', () async {
      final c = make(sink: RecordingCommandSink());
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
      clock.set(s(5));
      await owner(c).selectSource(3);
      expect(amp(c).pendingVolumeDb!.deadline, s(5, 400));
    });

    test('trace: a switch produces send source, then rx and view lines carrying source=', () async {
      final c = make(sink: RecordingCommandSink(), traced: true);
      seedFromControlView(owner(c), ControlViewState.forScenario(DebugScenario.connected));
      traceLines.clear();
      await owner(c).selectSource(3);
      clock.set(s(0, 200));
      owner(c).ingest(on(volumeDb: -40, source: 3));
      expect(events(), [
        'view power=on db=-40.0 muted=false hasAmp=true source=3',
        'rx ip=$ip power=on raw=115 db=-40.0 source=3',
      ]);
    });
  });
}
