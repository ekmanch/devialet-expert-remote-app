/// Everything the Control screen renders, as one immutable value.
///
/// Task 2.0.x is UI-only: this is produced by a fake notifier
/// (`control_view_state_provider.dart`) driven from the debug bar. Task
/// 3.0.x's real state owner produces the same type from `DevialetStatus`,
/// which is why the field names line up with it (`isMuted`, `volumeDb`,
/// `activeSourceIndex`, slot `index` on [SourceItem]). Deliberately free
/// of Flutter imports.
library;

/// Owner decision 2026-09-19: a silent amp ("not responding") is presented
/// exactly like no amplifier selected — a phone cannot tell an amp that
/// stopped broadcasting from one that is unplugged. Hence two phases, not
/// three. (The *persisted* selection must still survive silence so the app
/// reconnects when broadcasts resume — Task 3.x, not this layer.)
enum ConnectionPhase { notConnected, connected }

enum PowerPhase { on, off, booting }

/// The scenarios the debug state driver cycles through (Task 2.0.12).
/// `notResponding` renders identically to `notConnected` (see
/// [ConnectionPhase]); it stays in the cycle so the decision is visible.
enum DebugScenario { connected, off, booting, notResponding, notConnected, muted }

extension DebugScenarioLabel on DebugScenario {
  String get label => switch (this) {
    DebugScenario.connected => 'Connected',
    DebugScenario.off => 'Off',
    DebugScenario.booting => 'Booting',
    DebugScenario.notResponding => 'Not responding',
    DebugScenario.notConnected => 'Not connected',
    DebugScenario.muted => 'Muted',
  };
}

/// One row of the amp sheet. [model] is the mDNS-resolved make/model and
/// may be unknown; [name] is the amp's own UDP broadcast name.
class AmpRef {
  const AmpRef({required this.id, required this.name, this.model, required this.ip});

  final String id;
  final String name;
  final String? model;
  final String ip;

  /// TODO 2.0.2 / 2.0.3: `model ?? name` everywhere an amp is named.
  String get displayName => model ?? name;
  bool get isResolved => model != null;

  @override
  bool operator ==(Object other) => other is AmpRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// An *enabled* source slot. [index] is the status-broadcast slot index
/// (0–29) so Task 3.8.x can send it straight to `selectSource`.
class SourceItem {
  const SourceItem({required this.index, required this.name});

  final int index;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is SourceItem && other.index == index && other.name == name;

  @override
  int get hashCode => Object.hash(index, name);
}

const Object _unset = Object();

class ControlViewState {
  const ControlViewState({
    required this.connection,
    required this.selectedAmp,
    required this.knownAmps,
    required this.power,
    required this.isMuted,
    required this.volumeDb,
    required this.floorDb,
    required this.ceilingDb,
    required this.sources,
    required this.activeSourceIndex,
  });

  final ConnectionPhase connection;

  /// `null` == "None" / "No Amplifier".
  final AmpRef? selectedAmp;
  final List<AmpRef> knownAmps;
  final PowerPhase power;
  final bool isMuted;

  /// Last-known value; kept (and shown dimmed) while Off / Booting
  /// (TODO 2.0.8).
  final double volumeDb;

  /// Dial range. Parameters, not constants — they become the floor /
  /// ceiling settings in Task 3.4.x (TODO 2.0.4).
  final double floorDb;
  final double ceilingDb;

  /// Enabled slots only; empty == the sheet's empty state.
  final List<SourceItem> sources;
  final int? activeSourceIndex;

  // ---- Gating, in one place so every input path is covered (checklist 6).

  bool get hasAmp => selectedAmp != null && connection == ConnectionPhase.connected;

  /// Amp selected and reachable, but Off or Booting: everything except
  /// power is inert.
  bool get ampInert => hasAmp && power != PowerPhase.on;

  bool get volumeGroupEnabled => hasAmp && !ampInert;

  bool get powerEnabled => hasAmp && power != PowerPhase.booting;

  SourceItem? get activeSource {
    for (final s in sources) {
      if (s.index == activeSourceIndex) return s;
    }
    return null;
  }

  ControlViewState copyWith({
    ConnectionPhase? connection,
    Object? selectedAmp = _unset,
    List<AmpRef>? knownAmps,
    PowerPhase? power,
    bool? isMuted,
    double? volumeDb,
    double? floorDb,
    double? ceilingDb,
    List<SourceItem>? sources,
    Object? activeSourceIndex = _unset,
  }) {
    return ControlViewState(
      connection: connection ?? this.connection,
      selectedAmp: identical(selectedAmp, _unset) ? this.selectedAmp : selectedAmp as AmpRef?,
      knownAmps: knownAmps ?? this.knownAmps,
      power: power ?? this.power,
      isMuted: isMuted ?? this.isMuted,
      volumeDb: volumeDb ?? this.volumeDb,
      floorDb: floorDb ?? this.floorDb,
      ceilingDb: ceilingDb ?? this.ceilingDb,
      sources: sources ?? this.sources,
      activeSourceIndex: identical(activeSourceIndex, _unset)
          ? this.activeSourceIndex
          : activeSourceIndex as int?,
    );
  }

  // ---- Fixtures. TEST-NET-1 addresses (192.0.2.0/24, RFC 5737) so a fake
  // can never target real hardware (checklist 27).

  static const AmpRef fixtureAmp = AmpRef(
    id: 'amp-1',
    name: 'My Devialet',
    model: 'Devialet Expert 140 Pro',
    ip: '192.0.2.22',
  );

  static const List<AmpRef> fixtureAmps = [
    fixtureAmp,
    AmpRef(id: 'amp-2', name: 'Living Room', model: 'Devialet Expert 220 Pro', ip: '192.0.2.23'),
    // mDNS unresolved — falls back to the UDP name, per the mockup.
    AmpRef(id: 'amp-3', name: 'Devialet-ETH', ip: '192.0.2.24'),
  ];

  /// The six mockup source names. Names are per-unit and only ever come
  /// from the live broadcast in the real app (docs/protocol.md).
  static const List<SourceItem> fixtureSources = [
    SourceItem(index: 0, name: 'Optical 1'),
    SourceItem(index: 1, name: 'UPnP'),
    SourceItem(index: 2, name: 'Roon Ready'),
    SourceItem(index: 3, name: 'AirPlay'),
    SourceItem(index: 4, name: 'Spotify'),
    SourceItem(index: 14, name: 'AIR'),
  ];

  static const ControlViewState connectedFixture = ControlViewState(
    connection: ConnectionPhase.connected,
    selectedAmp: fixtureAmp,
    knownAmps: fixtureAmps,
    power: PowerPhase.on,
    isMuted: false,
    volumeDb: -25.0,
    floorDb: -60.0,
    ceilingDb: -15.0,
    sources: fixtureSources,
    activeSourceIndex: 0,
  );

  factory ControlViewState.forScenario(DebugScenario scenario) {
    const base = connectedFixture;
    return switch (scenario) {
      DebugScenario.connected => base,
      DebugScenario.off => base.copyWith(power: PowerPhase.off),
      DebugScenario.booting => base.copyWith(power: PowerPhase.booting),
      DebugScenario.muted => base.copyWith(isMuted: true),
      // Amp was selected, then went silent: list emptied, selection shown
      // as None (owner decision, see ConnectionPhase).
      DebugScenario.notResponding => base.copyWith(
        connection: ConnectionPhase.notConnected,
        selectedAmp: null,
        knownAmps: const <AmpRef>[],
        sources: const <SourceItem>[],
        activeSourceIndex: null,
      ),
      // Never chose / chose None: amps are on the LAN, none selected.
      DebugScenario.notConnected => base.copyWith(
        connection: ConnectionPhase.notConnected,
        selectedAmp: null,
        sources: const <SourceItem>[],
        activeSourceIndex: null,
      ),
    };
  }
}
