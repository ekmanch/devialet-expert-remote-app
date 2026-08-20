import 'dart:async';
import 'dart:typed_data';

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
class NoDeviceIpSetException implements Exception {
  @override
  String toString() => 'DevialetClient: no device IP set';
}

/// Orchestrates the UDP protocol: packet sequencing (fire-and-forget,
/// sent-twice, no ack), the documented app-level command ordering rule
/// (source-select always followed by a forced volume set), and passive
/// status-broadcast listening. No Flutter dependency — see CLAUDE.md's
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
  String? deviceIp;

  /// Forced post-source-switch volume (`docs/known-gotchas.md` #5) — sent
  /// unconditionally after every source switch to compensate for the amp's
  /// own inconsistent per-input startup volume. This is a deliberate
  /// product decision, not a redundant network call — do not remove.
  static const double sourceSwitchVolumeDb = -40.0;

  Future<void> setPower(bool isOn) => _sendTwice(isOn ? CommandPayloads.powerOn : CommandPayloads.powerOff);

  Future<void> setMute(bool isMuted) =>
      _sendTwice(isMuted ? CommandPayloads.muteOn : CommandPayloads.muteOff);

  Future<void> setVolumeDb(double dbIn, {double maxDb = VolumeCodec.defaultSafetyMaxDb}) {
    return _sendTwice(CommandPayloads.setVolume(dbIn, maxDb: maxDb));
  }

  /// Sends the select-source command, then unconditionally forces the
  /// volume to [sourceSwitchVolumeDb] — see the field doc above. The two
  /// sends happen in that order, sequentially.
  Future<void> selectSource(int statusIndex) async {
    await _sendTwice(CommandPayloads.selectSource(statusIndex));
    await setVolumeDb(sourceSwitchVolumeDb);
  }

  Future<void> _sendTwice(CommandPayload payload) {
    final ip = deviceIp;
    if (ip == null) throw NoDeviceIpSetException();

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

  StreamSubscription<Uint8List>? _statusSubscription;
  final StreamController<DevialetStatus> _statusController = StreamController<DevialetStatus>.broadcast();

  /// Emits every successfully-parsed status broadcast. Malformed/undersized
  /// packets are silently dropped upstream (see [DevialetStatus.tryParse])
  /// and never reach this stream — matching the original app's behavior of
  /// never surfacing a parse failure to the UI.
  Stream<DevialetStatus> get statusStream => _statusController.stream;

  /// Starts listening for status broadcasts. In the original app this is
  /// tied to `onResume()`/`onPause()`; here it's an explicit call so the
  /// domain layer can decide when that should happen (Flutter's lifecycle
  /// hooks differ from Android's Activity lifecycle).
  void startListening() {
    _statusSubscription ??= _transport.bindAndListen(DevialetProtocol.statusPort).listen((data) {
      final status = DevialetStatus.tryParse(data);
      if (status != null) _statusController.add(status);
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
