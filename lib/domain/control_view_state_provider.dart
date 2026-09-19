import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'control_view_state.dart';

/// Fake owner of [ControlViewState] for Task 2.0.x. Every intent the UI
/// can emit lands here; each one no-ops when the state's own gating
/// getters say the control is unavailable, so the gate exists once
/// (checklist 6). Semantics are deliberately simple and *timer-free*
/// (Booting stays Booting until the debug bar moves on) so widget tests
/// are deterministic; the real owner (Task 3.x) replaces this class.
class ControlViewNotifier extends Notifier<ControlViewState> {
  ControlViewNotifier({this.initial, this.initialScenario = DebugScenario.connected});

  final ControlViewState? initial;
  final DebugScenario initialScenario;
  late DebugScenario _scenario = initialScenario;

  /// The scenario most recently applied by the debug driver.
  DebugScenario get scenario => _scenario;

  @override
  ControlViewState build() => initial ?? ControlViewState.forScenario(_scenario);

  // ---- Debug driver (Task 2.0.12)

  void applyScenario(DebugScenario scenario) {
    _scenario = scenario;
    state = ControlViewState.forScenario(scenario);
  }

  void cycleScenario({int step = 1}) {
    final values = DebugScenario.values;
    applyScenario(values[(_scenario.index + step) % values.length]);
  }

  // ---- UI intents

  void toggleMute() {
    if (!state.volumeGroupEnabled) return;
    state = state.copyWith(isMuted: !state.isMuted);
  }

  void togglePower() {
    if (!state.powerEnabled) return;
    state = switch (state.power) {
      PowerPhase.on => state.copyWith(power: PowerPhase.off),
      PowerPhase.off => state.copyWith(power: PowerPhase.booting),
      PowerPhase.booting => state,
    };
  }

  void setVolumeDb(double db) {
    if (!state.volumeGroupEnabled) return;
    state = state.copyWith(volumeDb: db.clamp(state.floorDb, state.ceilingDb));
  }

  void stepVolume(int direction, {double stepDb = 1.0}) =>
      setVolumeDb(state.volumeDb + direction * stepDb);

  void selectSource(int index) {
    if (!state.volumeGroupEnabled) return;
    if (!state.sources.any((s) => s.index == index)) return;
    state = state.copyWith(activeSourceIndex: index);
  }

  /// `null` == the sheet's "None" row. Selecting an amp lands on a known
  /// on/unmuted state, as the mockup does; the real app reflects whatever
  /// the newly selected amp broadcasts.
  void selectAmp(AmpRef? amp) {
    if (amp == null) {
      state = state.copyWith(
        connection: ConnectionPhase.notConnected,
        selectedAmp: null,
        sources: const <SourceItem>[],
        activeSourceIndex: null,
      );
      return;
    }
    state = state.copyWith(
      connection: ConnectionPhase.connected,
      selectedAmp: amp,
      knownAmps: state.knownAmps.contains(amp) ? state.knownAmps : [amp, ...state.knownAmps],
      power: PowerPhase.on,
      isMuted: false,
      sources: ControlViewState.fixtureSources,
      activeSourceIndex: ControlViewState.fixtureSources.first.index,
    );
  }

  void addManualAmp(String ip) {
    selectAmp(AmpRef(id: 'manual-$ip', name: 'New Amplifier', ip: ip));
  }
}

final controlViewStateProvider = NotifierProvider<ControlViewNotifier, ControlViewState>(
  ControlViewNotifier.new,
);
