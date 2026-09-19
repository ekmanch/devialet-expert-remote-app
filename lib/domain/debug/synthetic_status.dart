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
      volumeRaw: (volumeDb * 2 + 195).round(),
    ),
  )!;
  return (senderIp: ip, status: status);
}

/// One broadcast per amp of a fixture shape: the selected amp carries the
/// shape's power/mute/volume/source, the others are plain online amps.
List<AmpStatusReport> reportsFor(ControlViewState shape) {
  final selected = shape.selectedAmp;
  return [
    for (final amp in shape.knownAmps)
      if (amp != selected) syntheticReport(ip: amp.ip, name: amp.name),
    if (selected != null)
      syntheticReport(
        ip: selected.ip,
        name: selected.name,
        isPoweredOn: shape.power == PowerPhase.on,
        isMuted: shape.isMuted,
        volumeDb: shape.volumeDb,
        sources: shape.sources,
        activeSourceIndex: shape.activeSourceIndex ?? 0,
      ),
  ];
}

/// Drives [owner] to present [shape]: ingest every amp, resolve model
/// names, set the selection and dial range, and mark a boot in progress.
/// After this, `deriveControlView(owner.state)` equals [shape] (with the
/// same `selectedIp`).
void seedFromControlView(AmpStateOwner owner, ControlViewState shape) {
  for (final report in reportsFor(shape)) {
    owner.ingest(report);
  }
  for (final amp in shape.knownAmps) {
    if (amp.model != null) owner.setModelName(amp.ip, amp.model);
  }
  final selected = shape.selectedAmp;
  if (selected != null) {
    if (selected.model != null) owner.setModelName(selected.ip, selected.model);
    if (shape.power == PowerPhase.booting) owner.markBooting(selected.ip);
    owner.selectIp(selected.ip);
  } else {
    owner.selectIp(shape.selectedIp);
  }
  owner.setVolumeRange(floorDb: shape.floorDb, ceilingDb: shape.ceilingDb);
}
