/// Everything the Control screen renders, as one immutable value.
///
/// Produced by `deriveControlView` in `amp_state.dart` from the owner's raw
/// model (Task 3.0.x); the field names line up with `DevialetStatus`
/// (`isMuted`, `volumeDb`, `activeSourceIndex`, slot `index` on
/// [SourceItem]). The fixtures below are the debug simulated amp's and the
/// widget tests' shapes. Deliberately free of Flutter imports.
library;

/// Three phases (owner's v44 mockups, 2026-09-24, revising the 2026-09-19
/// "no third presentation" decision recorded at TODO 3.0.8):
///
/// - `notConnected`: nothing is selected — the user chose None, or never
///   chose and 0 or 2+ amps are known. "No Amplifier / Tap to connect".
/// - `waiting`: something *is* selected (explicitly, or the lone amp by
///   auto-select) but it is not reachable — silent for 8 s, or a typed
///   IP never heard from. The selection stays checked in the sheet and
///   named on the card ("Reconnecting…" / "Connecting…"); every control
///   is inert ([ControlViewState.hasAmp] is false) and there is no
///   reading. The *persisted* selection survives silence so the next
///   broadcast reconnects without a tap (Task 3.0.8).
/// - `connected`: the selected amp is broadcasting.
enum ConnectionPhase { notConnected, waiting, connected }

enum PowerPhase { on, off, booting }

/// Which sheet is visible, as the owner's one slot (Task 3.8.2 / 3.0.6).
/// One value, so the two sheets are mutually exclusive by construction;
/// expressed as *what is visible*, not as a route, so a two-pane layout
/// (3.11.x) can render it as a pane instead. Never persisted.
enum SheetKind { none, amp, source }

/// The scenarios the debug state driver cycles through (Task 2.0.12).
/// `notResponding` is the [ConnectionPhase.waiting] shape: the chosen amp
/// (and, in the simulator, every simulated amp) went silent.
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

const Object _unset = Object();

/// One row of the amp sheet (Task 3.9.0: every amp ever heard, plus the
/// selection when it was never heard). [model] is the mDNS-resolved
/// make/model and may be unknown; [name] is the amp's own UDP broadcast
/// name, empty only for a never-heard selection.
class AmpRef {
  const AmpRef({
    required this.id,
    required this.name,
    this.model,
    required this.ip,
    this.online = true,
    this.heard = true,
    this.manual = false,
    this.silentFor,
  });

  final String id;
  final String name;
  final String? model;
  final String ip;

  /// Broadcasting within the last 8 s.
  final bool online;

  /// False only for the synthetic row of a selected IP that has never
  /// broadcast (a typed IP, or a restored selection before its first
  /// packet). Such a row is never [online].
  final bool heard;

  /// Typed in this process and not yet heard: the sheet's "MANUAL" tag.
  /// Transient — after a restart the app cannot tell a typed IP from a
  /// discovered one, so the tag does not come back (owner decision
  /// 2026-09-24, Task 3.9.3).
  final bool manual;

  /// How long the amp has been silent, **quantized** to what the sheet
  /// prints ("just now" under a minute, whole minutes under an hour, whole
  /// hours beyond) so the view's value equality keeps suppressing rebuilds
  /// on every tick. `null` while [online] or never [heard].
  final Duration? silentFor;

  /// TODO 2.0.2 / 2.0.3: `model ?? name` everywhere an amp is named; the IP
  /// when neither is known (mockup `modelName || name || ip`).
  String get displayName => model ?? (name.isEmpty ? ip : name);
  bool get isResolved => model != null;

  AmpRef copyWith({bool? online, bool? heard, bool? manual, Object? silentFor = _unset}) => AmpRef(
    id: id,
    name: name,
    model: model,
    ip: ip,
    online: online ?? this.online,
    heard: heard ?? this.heard,
    manual: manual ?? this.manual,
    silentFor: identical(silentFor, _unset) ? this.silentFor : silentFor as Duration?,
  );

  @override
  bool operator ==(Object other) =>
      other is AmpRef &&
      other.id == id &&
      other.name == name &&
      other.model == model &&
      other.ip == ip &&
      other.online == online &&
      other.heard == heard &&
      other.manual == manual &&
      other.silentFor == silentFor;

  @override
  int get hashCode => Object.hash(id, name, model, ip, online, heard, manual, silentFor);
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
    required this.stepDb,
    required this.sources,
    required this.activeSourceIndex,
    this.selectedIp,
    this.visibleSheet = SheetKind.none,
  });

  final ConnectionPhase connection;

  /// `null` == "None" / "No Amplifier" (nothing selected). While
  /// [ConnectionPhase.waiting] this is the selected amp as last known —
  /// or a synthetic, never-[AmpRef.heard] ref for a typed / restored IP —
  /// so the card and the sheet can name it.
  final AmpRef? selectedAmp;

  /// The owner's *explicit* selection, independent of whether that amp is
  /// reachable (an auto-selected lone amp leaves this null).
  final String? selectedIp;

  /// Every amp ever heard (the map never evicts), online ones first, then
  /// the silent ones, each group in numeric IP order (Task 3.9.0, KDE);
  /// plus the never-heard selection, last, when there is one.
  final List<AmpRef> knownAmps;
  final PowerPhase power;
  final bool isMuted;

  /// Last-known value; kept (and shown dimmed) while Off / Booting
  /// (TODO 2.0.8). **`null` when there is no amp** (Task 3.9.4, checklist
  /// 5): "no reading" is the absence of a value, never a sentinel that a
  /// clamp could turn into a plausible number.
  final double? volumeDb;

  /// Dial range. Parameters, not constants — they become the floor /
  /// ceiling settings in Task 3.4.x (TODO 2.0.4).
  final double floorDb;
  final double ceilingDb;

  /// The configured step (Task 3.6.0): what one VOL ± input moves and
  /// what the dial snaps to. From the settings, like the range.
  final double stepDb;

  /// Enabled slots only; empty == the sheet's empty state.
  final List<SourceItem> sources;
  final int? activeSourceIndex;

  /// The owner's sheet slot (Task 3.8.2). The Control screen pushes the
  /// matching route when this leaves `none` and every route completion
  /// writes `none` back; a sheet pops itself when this stops naming it.
  final SheetKind visibleSheet;

  // ---- Gating, in one place so every input path is covered (checklist 6).

  bool get hasAmp => selectedAmp != null && connection == ConnectionPhase.connected;

  /// Selected but unreachable (silent, or never heard). Presentation only;
  /// every gate keys on [hasAmp].
  bool get isWaiting => connection == ConnectionPhase.waiting;

  /// Amp selected and reachable, but Off or Booting: everything except
  /// power is inert.
  bool get ampInert => hasAmp && power != PowerPhase.on;

  /// Task 3.2.1: the one predicate every non-power entry point gates
  /// through — the amp drops commands unless it is On and reachable.
  ///
  /// Task 3.5.1 — every entry point, enumerated (checklist items 6, 28):
  ///
  /// | Entry point            | Widget gate                                   | Owner gate      |
  /// |------------------------|-----------------------------------------------|-----------------|
  /// | dial drag / snap       | `VolumeDial.enabled` + `DimmedGroup(dialWrap)` | `setVolumeDb`   |
  /// | VOL − / +              | `VolumeButtons.enabled` + `DimmedGroup(dialWrap)` | `stepVolume` |
  /// | mute                   | `MuteButton.enabled` + two `DimmedGroup`s      | `toggleMute`    |
  /// | power                  | `PowerButton.enabled` ([powerCommandAllowed])  | `togglePower`   |
  /// | source trigger         | `DimmedGroup(sourceTrigger, blockTaps: hasAmp)` | — (`openSheet`, ungated: the empty-state sheet is reachable with no amp) |
  /// | source sheet rows      | `DimmedGroup(sourceRows)` + row `enabled`      | `selectSource`  |
  /// | sheet open / close     | trigger gates above; every route completion writes back | `openSheet` / `closeSheet` (not amp commands); the source sheet auto-closes on the On→not-On edge (3.8.2) |
  /// | amp sheet rows / None / manual IP | none, by design                     | none — selection is not an amp command |
  /// | device card, gear      | always live (open a sheet / Settings)          | —               |
  /// | VOL ± screen-reader tap (no pointer) | `AdaptivePressable.enabled` nulls `onTap` | `stepVolume` (3.6.1) |
  /// | hardware keys / Shortcuts / Actions | none exist                        | —               |
  /// | debug bar              | `kDebugMode`; drives `ingest`, not intents     | bypassed by design |
  ///
  /// Boundary: the widget flags cover pointer input; the owner's check on
  /// this predicate is the structural guarantee for every programmatic
  /// caller; the debug bar is outside both on purpose.
  bool get commandsAllowed => hasAmp && power == PowerPhase.on;

  /// Power is live while Off or On and inert while Booting.
  bool get powerCommandAllowed => hasAmp && power != PowerPhase.booting;

  /// Presentation aliases of the predicates above (same truth table).
  bool get volumeGroupEnabled => commandsAllowed;

  bool get powerEnabled => powerCommandAllowed;

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
    Object? volumeDb = _unset,
    double? floorDb,
    double? ceilingDb,
    double? stepDb,
    List<SourceItem>? sources,
    Object? activeSourceIndex = _unset,
    Object? selectedIp = _unset,
    SheetKind? visibleSheet,
  }) {
    return ControlViewState(
      connection: connection ?? this.connection,
      selectedAmp: identical(selectedAmp, _unset) ? this.selectedAmp : selectedAmp as AmpRef?,
      knownAmps: knownAmps ?? this.knownAmps,
      power: power ?? this.power,
      isMuted: isMuted ?? this.isMuted,
      volumeDb: identical(volumeDb, _unset) ? this.volumeDb : (volumeDb as num?)?.toDouble(),
      floorDb: floorDb ?? this.floorDb,
      ceilingDb: ceilingDb ?? this.ceilingDb,
      stepDb: stepDb ?? this.stepDb,
      sources: sources ?? this.sources,
      activeSourceIndex: identical(activeSourceIndex, _unset)
          ? this.activeSourceIndex
          : activeSourceIndex as int?,
      selectedIp: identical(selectedIp, _unset) ? this.selectedIp : selectedIp as String?,
      visibleSheet: visibleSheet ?? this.visibleSheet,
    );
  }

  /// Value equality so the derived provider suppresses rebuilds when a
  /// 5 Hz broadcast changes nothing visible (KDE `states_equal`).
  @override
  bool operator ==(Object other) =>
      other is ControlViewState &&
      other.connection == connection &&
      other.selectedAmp == selectedAmp &&
      other.selectedIp == selectedIp &&
      _listEquals(other.knownAmps, knownAmps) &&
      other.power == power &&
      other.isMuted == isMuted &&
      other.volumeDb == volumeDb &&
      other.floorDb == floorDb &&
      other.ceilingDb == ceilingDb &&
      other.stepDb == stepDb &&
      _listEquals(other.sources, sources) &&
      other.activeSourceIndex == activeSourceIndex &&
      other.visibleSheet == visibleSheet;

  @override
  int get hashCode => Object.hash(
    connection,
    selectedAmp,
    selectedIp,
    Object.hashAll(knownAmps),
    power,
    isMuted,
    volumeDb,
    floorDb,
    ceilingDb,
    stepDb,
    Object.hashAll(sources),
    activeSourceIndex,
    visibleSheet,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ---- Fixtures. TEST-NET-1 addresses (192.0.2.0/24, RFC 5737) so a fake
  // can never target real hardware (checklist 27).

  static const AmpRef fixtureAmp = AmpRef(
    id: '192.0.2.22',
    name: 'My Devialet',
    model: 'Devialet Expert 140 Pro',
    ip: '192.0.2.22',
  );

  static const List<AmpRef> fixtureAmps = [
    fixtureAmp,
    AmpRef(id: '192.0.2.23', name: 'Living Room', model: 'Devialet Expert 220 Pro', ip: '192.0.2.23'),
    // mDNS unresolved — falls back to the UDP name, per the mockup.
    AmpRef(id: '192.0.2.24', name: 'Devialet-ETH', ip: '192.0.2.24'),
  ];

  /// [fixtureAmps] as the derivation presents them 8 s after their last
  /// broadcast: offline, `silentFor` in the "just now" bucket.
  static final List<AmpRef> silentFixtureAmps = [
    for (final a in fixtureAmps) a.copyWith(online: false, silentFor: Duration.zero),
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
    stepDb: 0.5,
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
      // Every simulated amp went silent 8 s ago (the sim stops all its
      // broadcasts): the selection stays, waiting; the rows sit under
      // "Not responding" with "Last seen just now".
      DebugScenario.notResponding => base.copyWith(
        connection: ConnectionPhase.waiting,
        selectedAmp: silentFixtureAmps.first,
        knownAmps: silentFixtureAmps,
        power: PowerPhase.off,
        isMuted: false,
        volumeDb: null,
        sources: const <SourceItem>[],
        activeSourceIndex: null,
      ),
      // Never chose / chose None: amps are on the LAN, none selected.
      // No amp: no reading (checklist 5), power Off, unmuted, no sources.
      DebugScenario.notConnected => base.copyWith(
        connection: ConnectionPhase.notConnected,
        selectedAmp: null,
        power: PowerPhase.off,
        isMuted: false,
        volumeDb: null,
        sources: const <SourceItem>[],
        activeSourceIndex: null,
      ),
    };
  }
}
