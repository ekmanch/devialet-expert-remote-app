import 'package:devialet_expert_remote_app/networking/devialet_client.dart';
import 'package:devialet_expert_remote_app/networking/status_packet.dart';
import 'package:devialet_expert_remote_app/networking/status_packet_builder.dart';

/// Builds a parsed status through the real packet layout.
DevialetStatus statusOf({
  String name = 'My Devialet-ETH',
  bool power = true,
  bool muted = false,
  double volumeDb = -25.0,
  int active = 0,
  List<({int index, bool enabled, String name})> sources = const [
    (index: 0, enabled: true, name: 'Optical 1'),
    (index: 3, enabled: true, name: 'AirPlay'),
    (index: 5, enabled: false, name: 'Disabled'),
  ],
}) {
  return DevialetStatus.tryParse(
    buildStatusPacket(
      deviceName: name,
      sources: sources,
      isPoweredOn: power,
      isMuted: muted,
      activeSourceIndex: active,
      volumeRaw: (volumeDb * 2 + 195).round(),
    ),
  )!;
}

AmpStatusReport reportFrom(
  String ip, {
  String name = 'My Devialet-ETH',
  bool power = true,
  bool muted = false,
  double volumeDb = -25.0,
  int active = 0,
}) => (senderIp: ip, status: statusOf(name: name, power: power, muted: muted, volumeDb: volumeDb, active: active));
