import 'dart:async';

import 'command_packet.dart';
import 'command_payloads.dart';
import 'packet_counters.dart';
import 'protocol_constants.dart';
import 'status_packet.dart';
import 'udp_transport.dart';
import 'volume_codec.dart';

/// Thrown when a command is issued before a target amp IP has been set.
/// Mirrors the original app's `requireIp {}` gate, enforced here instead of
/// pushed onto callers.
/// A parsed broadcast together with the IP it came from. The state owner
/// keys its discovery map on [senderIp] and only lets the selected amp's
/// reports touch live control state.
typedef AmpStatusReport = ({String senderIp, DevialetStatus status});

class NoDeviceIpSetException implements Exception {
  @override
  String toString() => 'DevialetClient: no device IP set';
}

/// Orchestrates the UDP protocol: packet sequencing (fire-and-forget,
/// sent-twice, no ack), the documented app-level command ordering rule
/// (source-select always followed by the caller's forced volume set, in
/// one invocation), and passive status-broadcast listening. No Flutter dependency — see CLAUDE.md's
/// "Core protocol logic... isolated from UI/state layers" requirement.
///
/// This class deliberately does **not** implement discovery, staleness
/// tracking, or the volume-change debounce windows from
/// `docs/known-gotchas.md` #1-#2 — those are app-level/domain-layer
/// concerns for the next phase, not wire-protocol behavior.
class DevialetClient {
  DevialetClient({required UdpTransport transport, this.deviceIp}) : _transport = transport;

  final UdpTransport _transport;
  final PacketCounters _counters = PacketCounters();

  /// Target amp IP for outgoing commands. `null` means no amp selected.
  /// Read **once** per public call (see [_requireIp]) so a multi-send
  /// command cannot be retargeted between its sends.
  String? deviceIp;

  Future<void> setPower(bool isOn) => _sendTwice(isOn ? CommandPayloads.powerOn : CommandPayloads.powerOff);

  Future<void> setMute(bool isMuted) =>
      _sendTwice(isMuted ? CommandPayloads.muteOn : CommandPayloads.muteOff);

  /// [maxDb] is the wire-side ceiling, required (Task 1.1.3); `null` is the
  /// explicit "unbounded". See [VolumeCodec.encodeCommandWord].
  Future<void> setVolumeDb(double dbIn, {required double? maxDb}) {
    return _sendTwice(CommandPayloads.setVolume(dbIn, maxDb: maxDb));
  }

  /// Sends the select-source command, then unconditionally the forced
  /// post-switch volume [postSwitchDb] (`docs/known-gotchas.md` #5: the
  /// amp remembers a volume per input, which reads as random; the app's
  /// startup-volume setting overrides it — a deliberate product decision,
  /// not a redundant network call, do not remove). Source×2 then volume×2
  /// in one invocation with no delay (★ 6/6 measured); [maxDb] clamps the
  /// forced volume like any other. Both pairs go to the IP read at the
  /// call, even if [deviceIp] changes while the first pair is in flight.
  Future<void> selectSource(int statusIndex, {required double postSwitchDb, required double? maxDb}) async {
    final ip = _requireIp();
    await _sendTwiceTo(ip, CommandPayloads.selectSource(statusIndex));
    await _sendTwiceTo(ip, CommandPayloads.setVolume(postSwitchDb, maxDb: maxDb));
  }

  String _requireIp() {
    final ip = deviceIp;
    if (ip == null) throw NoDeviceIpSetException();
    return ip;
  }

  Future<void> _sendTwice(CommandPayload payload) => _sendTwiceTo(_requireIp(), payload);

  Future<void> _sendTwiceTo(String ip, CommandPayload payload) {
    final firstCounters = _counters.next();
    final secondCounters = _counters.next();
    final first = CommandPacket(
      packetCounter: firstCounters.packetCounter,
      commandCounter: firstCounters.commandCounter,
      payload: payload,
    ).encode();
    final second = CommandPacket(
      packetCounter: secondCounters.packetCounter,
      commandCounter: secondCounters.commandCounter,
      payload: payload,
    ).encode();

    return _transport.sendTwice(first, second, ip, DevialetProtocol.commandPort);
  }

  StreamSubscription<UdpDatagram>? _statusSubscription;
  final StreamController<AmpStatusReport> _statusController = StreamController<AmpStatusReport>.broadcast();

  /// Emits every successfully-parsed status broadcast. Malformed/undersized
  /// packets are silently dropped upstream (see [DevialetStatus.tryParse])
  /// and never reach this stream — matching the original app's behavior of
  /// never surfacing a parse failure to the UI. Each report carries the
  /// sender IP (see [AmpStatusReport]).
  Stream<AmpStatusReport> get statusReports => _statusController.stream;

  /// Starts listening for status broadcasts. In the original app this is
  /// tied to `onResume()`/`onPause()`; here it's an explicit call so the
  /// domain layer can decide when that should happen (Flutter's lifecycle
  /// hooks differ from Android's Activity lifecycle).
  void startListening() {
    _statusSubscription ??= _transport.bindAndListen(DevialetProtocol.statusPort).listen((datagram) {
      final status = DevialetStatus.tryParse(datagram.data);
      if (status != null) _statusController.add((senderIp: datagram.senderAddress, status: status));
    }, onError: (_) {});
  }

  Future<void> stopListening() async {
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    _transport.close();
  }

  Future<void> dispose() async {
    await stopListening();
    await _statusController.close();
  }
}
