import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/amp_state_owner.dart';
import '../../domain/control_view_state.dart';
import '../../domain/debug/synthetic_status.dart';

/// Debug-only simulated amplifier(s) on TEST-NET-1 addresses (192.0.2.x,
/// never routable — checklist item 27), broadcasting through the owner's
/// real ingest path at the amp's real 5 Hz so every presentation is one
/// tap away without hardware, next to any real amp on the LAN.
///
/// Opt-in: nothing is simulated until the debug bar's first tap, so a
/// fresh debug build shows the real LAN. Applying a scenario re-selects
/// the simulated amp (a real one is shadowed until picked in the sheet).
///
/// Limits until later tasks land: Booting is only a 20 s boot deadline
/// (it falls back to Off when it expires, Task 3.2.x); an optimistic
/// mute/power/volume change reverts after 400 ms because nothing is sent
/// yet (Tasks 3.5–3.9); "Not responding" simply stops broadcasting and
/// the view flips after the real 8 s staleness.
class SimulatedAmp extends Notifier<DebugScenario> {
  static const Duration broadcastPeriod = Duration(milliseconds: 200);

  Timer? _timer;
  bool _active = false;
  bool _silent = false;

  bool get isActive => _active;

  @override
  DebugScenario build() {
    ref.onDispose(() => _timer?.cancel());
    return DebugScenario.connected;
  }

  AmpStateOwner get _owner => ref.read(ampStateProvider.notifier);

  void apply(DebugScenario scenario) {
    state = scenario;
    _active = true;
    _silent = scenario == DebugScenario.notResponding;
    _timer ??= Timer.periodic(broadcastPeriod, (_) => _broadcast());
    if (_silent) {
      // Keep the selection; the amp just goes quiet.
      _owner.selectIp(ControlViewState.fixtureAmp.ip);
      return;
    }
    seedFromControlView(_owner, ControlViewState.forScenario(scenario));
  }

  void cycle({int step = 1}) {
    final values = DebugScenario.values;
    apply(values[(state.index + step) % values.length]);
  }

  void _broadcast() {
    if (!_active || _silent) return;
    for (final report in reportsFor(ControlViewState.forScenario(state))) {
      _owner.ingest(report);
    }
  }
}

final simulatedAmpProvider = NotifierProvider<SimulatedAmp, DebugScenario>(SimulatedAmp.new);
