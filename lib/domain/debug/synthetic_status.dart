import '../../networking/devialet_client.dart';
import '../../networking/status_packet.dart';
import '../../networking/status_packet_builder.dart';
import '../amp_state_owner.dart';
import '../control_view_state.dart';

/// A status report built through the real packet layout (encode, then
/// `tryParse`), so synthetic amps exercise exactly the ingest path a real
/// broadcast takes. Pure Dart; used by the debug simulated amp and by
/// widget-test seeding.
AmpStatusReport syntheticReport({
  required String ip,
  required String name,
  bool isPoweredOn = true,
  bool isMuted = false,
  double volumeDb = -25.0,
  int? volumeRaw,
  List<SourceItem> sources = ControlViewState.fixtureSources,
  int activeSourceIndex = 0,
}) {
  final status = DevialetStatus.tryParse(
    buildStatusPacket(
      deviceName: name,
      sources: [for (final s in sources) (index: s.index, enabled: true, name: s.name)],
      isPoweredOn: isPoweredOn,
      isMuted: isMuted,
      activeSourceIndex: activeSourceIndex,
      volumeRaw: volumeRaw ?? (volumeDb * 2 + 195).round(),
    ),
  )!;
  return (senderIp: ip, status: status);
}

/// One broadcast per *heard* amp of a fixture shape: the selected amp
/// carries the shape's power/mute/volume/source, the others are plain
/// online amps. A never-heard selection (Task 3.9.3) has no packet.
List<AmpStatusReport> reportsFor(ControlViewState shape) {
  final selected = shape.selectedAmp;
  return [
    for (final amp in shape.knownAmps)
      if (amp != selected && amp.heard) syntheticReport(ip: amp.ip, name: amp.name),
    if (selected != null && selected.heard)
      syntheticReport(
        ip: selected.ip,
        name: selected.name,
        isPoweredOn: shape.power == PowerPhase.on,
        isMuted: shape.isMuted,
        volumeDb: shape.volumeDb ?? -25.0,
        sources: shape.sources,
        activeSourceIndex: shape.activeSourceIndex ?? 0,
      ),
  ];
}

/// Drives [owner] to present [shape]: ingest every amp, then
/// [seedSelectionFromControlView]. After this,
/// `deriveControlView(owner.state)` equals [shape] (with the same
/// `selectedIp`).
void seedFromControlView(AmpStateOwner owner, ControlViewState shape) {
  for (final report in reportsFor(shape)) {
    owner.ingest(report);
  }
  seedSelectionFromControlView(owner, shape);
}

/// The owner-side half of seeding: model names, silence (Task 3.9.0's
/// offline rows), the dial range (before any boot record so the startup
/// target uses the shape's range), the step size, a boot in progress for
/// the booting shape, and the selection (with its "typed" mark).
void seedSelectionFromControlView(AmpStateOwner owner, ControlViewState shape) {
  for (final amp in shape.knownAmps) {
    if (amp.model != null) owner.setModelName(amp.ip, amp.model);
    if (!amp.online && amp.heard) owner.seedSilent(amp.ip);
  }
  owner.setVolumeRange(floorDb: shape.floorDb, ceilingDb: shape.ceilingDb);
  owner.seedStepDb(shape.stepDb);
  final selected = shape.selectedAmp;
  if (selected != null) {
    if (selected.model != null) owner.setModelName(selected.ip, selected.model);
    if (shape.power == PowerPhase.booting) owner.markBooting(selected.ip);
    owner.seedSelection(selected.ip, manual: selected.manual);
  } else {
    owner.seedSelection(shape.selectedIp);
  }
}
