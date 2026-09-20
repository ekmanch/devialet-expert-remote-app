import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../amp_command_sink.dart';
import '../amp_state_owner.dart';
import '../control_view_state.dart';
import '../devialet_client_provider.dart';
import '../monotonic_clock.dart';
import '../settings/settings_owner.dart';
import 'synthetic_status.dart';

/// Debug-only simulated amplifier(s) on TEST-NET-1 addresses (192.0.2.x,
/// never routable — checklist item 27). Broadcasts through the owner's
/// real ingest path at the amp's real 5 Hz, and — since Task 3.2.x —
/// **behaves like the real amp under commands** so the boot machine, the
/// 500 ms startup-volume send and the post-boot hold can be soaked without
/// hardware:
///
/// | command | state | effect |
/// |---|---|---|
/// | power on | Off | boots: keeps broadcasting Off for 16 s, then On |
/// | power on | Booting / On | ignored |
/// | power off | any | immediate Off; remembers the last raw byte |
/// | volume (incl. startup) | Off / Booting, or < 200 ms after the first On | **dropped** (gotcha #9) |
/// | volume | On | applied after 100 ms; ends the misreport |
/// | mute / source | On | applied after 100 ms |
///
/// After a boot the first On packet carries the pre-shutdown byte, then
/// raw 111 (−42.0) until any volume command lands (gotcha #8). Deadlines
/// are evaluated on the sim's own 200 ms tick against the injected clock,
/// so tests drive it with a fake clock and [tick].
///
/// Opt-in: nothing is simulated until the debug bar's first tap. Applying
/// a scenario re-selects the simulated amp in memory only — never in the
/// persisted settings (checklist 19) — so a real amp is shadowed until
/// picked in the sheet, and the persisted choice returns on the next launch. "Not responding" stops broadcasting and the view
/// flips after the real 8 s. User volume / mute / source intents still
/// send nothing (Tasks 3.6–3.8), so those optimistic changes revert after
/// 400 ms — power and the startup volume are real.
class SimulatedAmp extends Notifier<DebugScenario> implements AmpCommandSink {
  static const Duration broadcastPeriod = Duration(milliseconds: 200);

  /// Real boots measured 15.0–18.6 s.
  static const Duration bootDuration = Duration(seconds: 16);
  static const Duration commandLatency = Duration(milliseconds: 100);

  /// Gotcha #9 cliff: the amp applied its own startup volume at up to
  /// +394 ms; the sim drops anything before +200 ms.
  static const Duration dropWindowAfterOn = Duration(milliseconds: 200);
  static const int misreportRaw = 111;

  static bool isTestNet(String ip) => ip.startsWith('192.0.2.');

  late MonotonicClock _clock;
  Timer? _timer;
  bool _active = false;
  bool _silent = false;
  final Map<String, SimAmp> _amps = {};

  bool get isActive => _active;

  /// Read-only view for tests.
  Map<String, SimAmp> get amps => Map.unmodifiable(_amps);

  @override
  DebugScenario build() {
    _clock = ref.watch(monotonicClockProvider);
    ref.onDispose(() => _timer?.cancel());
    return DebugScenario.connected;
  }

  AmpStateOwner get _owner => ref.read(ampStateProvider.notifier);

  Duration get _now => _clock.now();

  void apply(DebugScenario scenario) {
    state = scenario;
    _active = true;
    _silent = scenario == DebugScenario.notResponding;
    _timer ??= Timer.periodic(broadcastPeriod, (_) => tick());
    if (_silent) {
      // Keep the selection; the amp just goes quiet.
      _owner.seedSelection(ControlViewState.fixtureAmp.ip);
      return;
    }
    final shape = ControlViewState.forScenario(scenario);
    _seedAmps(shape);
    tick();
    seedSelectionFromControlView(_owner, shape);
  }

  void cycle({int step = 1}) {
    final values = DebugScenario.values;
    apply(values[(state.index + step) % values.length]);
  }

  void _seedAmps(ControlViewState shape) {
    _amps.clear();
    final selected = shape.selectedAmp;
    for (final amp in shape.knownAmps) {
      _amps[amp.ip] = SimAmp(name: amp.name, sources: ControlViewState.fixtureSources);
    }
    if (selected != null) {
      final sim = _amps.putIfAbsent(selected.ip, () => SimAmp(name: selected.name, sources: shape.sources));
      sim
        ..sources = shape.sources
        ..power = shape.power == PowerPhase.on
        ..muted = shape.isMuted
        ..volumeRaw = _rawFor(shape.volumeDb)
        ..source = shape.activeSourceIndex ?? 0;
      if (shape.power == PowerPhase.booting) sim.bootCompletesAt = _now + bootDuration;
    }
  }

  static int _rawFor(double db) => (db * 2 + 195).round();

  /// Advances every simulated amp to [MonotonicClock.now] and broadcasts.
  void tick() {
    final now = _now;
    for (final sim in _amps.values) {
      final bootDone = sim.bootCompletesAt;
      if (bootDone != null && now >= bootDone) {
        sim
          ..power = true
          ..bootCompletesAt = null
          ..firstOnAt = now
          ..firstOnPacketPending = true
          ..misreporting = true;
      }
      final due = sim.queue.where((e) => now >= e.$1).toList();
      sim.queue.removeWhere((e) => now >= e.$1);
      for (final e in due) {
        e.$2();
      }
    }
    if (!_active || _silent) return;
    for (final entry in _amps.entries) {
      final sim = entry.value;
      final raw = sim.firstOnPacketPending
          ? (sim.preShutdownRaw ?? sim.volumeRaw)
          : sim.misreporting
          ? misreportRaw
          : sim.volumeRaw;
      sim.firstOnPacketPending = false;
      _owner.ingest(
        syntheticReport(
          ip: entry.key,
          name: sim.name,
          isPoweredOn: sim.power,
          isMuted: sim.muted,
          volumeRaw: raw,
          sources: sim.sources,
          activeSourceIndex: sim.source,
        ),
      );
    }
  }

  // ---- AmpCommandSink for the simulated IPs (unknown IPs are swallowed)

  @override
  Future<void> setPower(String ip, bool on) async {
    final sim = _amps[ip];
    if (sim == null) return;
    if (on) {
      if (!sim.power && sim.bootCompletesAt == null) sim.bootCompletesAt = _now + bootDuration;
      return;
    }
    sim
      ..preShutdownRaw = sim.misreporting ? misreportRaw : sim.volumeRaw
      ..power = false
      ..bootCompletesAt = null
      ..firstOnAt = null
      ..firstOnPacketPending = false
      ..misreporting = false
      ..queue.clear();
  }

  bool _acceptsVolume(SimAmp sim) {
    if (!sim.power) return false;
    final firstOn = sim.firstOnAt;
    if (firstOn != null && _now - firstOn < dropWindowAfterOn) return false;
    return true;
  }

  void _queueVolume(SimAmp sim, double db) {
    sim.queue.add((
      _now + commandLatency,
      () => sim
        ..volumeRaw = _rawFor(db)
        ..misreporting = false,
    ));
  }

  @override
  Future<void> setVolumeDb(String ip, double db) async {
    final sim = _amps[ip];
    if (sim == null || !_acceptsVolume(sim)) return;
    _queueVolume(sim, db);
  }

  @override
  Future<void> sendStartupVolume(String ip, double db) => setVolumeDb(ip, db);

  @override
  Future<void> setMute(String ip, bool muted) async {
    final sim = _amps[ip];
    if (sim == null || !sim.power) return;
    sim.queue.add((_now + commandLatency, () => sim.muted = muted));
  }

  @override
  Future<void> selectSource(String ip, int statusIndex) async {
    final sim = _amps[ip];
    if (sim == null || !sim.power) return;
    sim.queue.add((_now + commandLatency, () => sim.source = statusIndex));
  }
}

/// Mutable state of one simulated amplifier.
class SimAmp {
  SimAmp({
    required this.name,
    required this.sources,
    this.power = true,
    this.muted = false,
    this.volumeRaw = 145,
    this.source = 0,
  });

  String name;
  List<SourceItem> sources;
  bool power;
  bool muted;
  int volumeRaw;
  int? preShutdownRaw;
  int source;
  Duration? bootCompletesAt;
  Duration? firstOnAt;
  bool firstOnPacketPending = false;
  bool misreporting = false;
  final List<(Duration, void Function())> queue = [];
}

final simulatedAmpProvider = NotifierProvider<SimulatedAmp, DebugScenario>(SimulatedAmp.new);

/// Debug builds: commands for TEST-NET IPs go to the simulated amp, every
/// other IP to the real sink. All of 192.0.2.0/24 is routed to the sim
/// whether or not it is active, so a fixture address never reaches a socket.
///
/// [simulated] is resolved lazily per call: the owner depends on the sink,
/// and the simulated amp reaches the owner to ingest, so a provider-level
/// `watch` here would be a dependency cycle.
class RoutingCommandSink implements AmpCommandSink {
  const RoutingCommandSink({required this.real, required this.simulated});

  final AmpCommandSink real;
  final AmpCommandSink Function() simulated;

  AmpCommandSink _for(String ip) => SimulatedAmp.isTestNet(ip) ? simulated() : real;

  @override
  Future<void> setVolumeDb(String ip, double db) => _for(ip).setVolumeDb(ip, db);

  @override
  Future<void> setMute(String ip, bool muted) => _for(ip).setMute(ip, muted);

  @override
  Future<void> setPower(String ip, bool on) => _for(ip).setPower(ip, on);

  @override
  Future<void> selectSource(String ip, int statusIndex) => _for(ip).selectSource(ip, statusIndex);

  @override
  Future<void> sendStartupVolume(String ip, double db) => _for(ip).sendStartupVolume(ip, db);
}

/// Installed by `main.dart` in debug builds and by the widget-test harness.
final debugCommandSinkOverride = ampCommandSinkProvider.overrideWith(
  (ref) => RoutingCommandSink(
    real: DevialetClientCommandSink(
      ref.watch(devialetClientProvider),
      ceilingDb: () => ref.read(settingsProvider).ceilingDb,
    ),
    simulated: () => ref.read(simulatedAmpProvider.notifier),
  ),
);
