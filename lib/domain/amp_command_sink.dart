import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../networking/devialet_client.dart';
import 'devialet_client_provider.dart';

/// Where the owner's intents send commands. The owner writes its
/// optimistic value *before* calling this and rolls that value back if the
/// call throws (checklist item 3; `docs/protocol.md`, reconciliation #6).
///
/// Since Task 3.2.x the default is [DevialetClientCommandSink], which
/// sends **power and the post-boot startup volume** for real and keeps the
/// user's volume / mute / source intents display-only (owner decision
/// 2026-09-19) until Tasks 3.6 / 3.7 / 3.8 flip them one at a time.
abstract interface class AmpCommandSink {
  Future<void> setVolumeDb(String ip, double db);
  Future<void> setMute(String ip, bool muted);
  Future<void> setPower(String ip, bool on);
  Future<void> selectSource(String ip, int statusIndex);

  /// Same opcode as [setVolumeDb], distinct intent: the machine's own
  /// post-boot correction (Task 3.2.2). Never unmutes (Task 3.7.1); the
  /// value comes from `AmpState.startupVolumeTarget`.
  Future<void> sendStartupVolume(String ip, double db);
}

class NoopCommandSink implements AmpCommandSink {
  const NoopCommandSink();

  @override
  Future<void> setVolumeDb(String ip, double db) async {}

  @override
  Future<void> setMute(String ip, bool muted) async {}

  @override
  Future<void> setPower(String ip, bool on) async {}

  @override
  Future<void> selectSource(String ip, int statusIndex) async {}

  @override
  Future<void> sendStartupVolume(String ip, double db) async {}
}

/// The real sink. `DevialetClient` targets its mutable `deviceIp`, read
/// synchronously inside `_sendTwice` before its first `await`, so
/// "set the IP, then call" in one synchronous run cannot interleave with
/// another caller (an explicit-IP client API is a 3.5/3.6 follow-up).
class DevialetClientCommandSink implements AmpCommandSink {
  DevialetClientCommandSink(this._client);

  final DevialetClient _client;

  @override
  Future<void> setPower(String ip, bool on) {
    _client.deviceIp = ip;
    return _client.setPower(on);
  }

  /// The client's default −15 dB ceiling is a second, wire-side clamp on
  /// top of the owner's (gotcha #6, defence in depth).
  @override
  Future<void> sendStartupVolume(String ip, double db) {
    _client.deviceIp = ip;
    return _client.setVolumeDb(db);
  }

  /// Task 3.6.x — display-only until then.
  @override
  Future<void> setVolumeDb(String ip, double db) async {}

  /// Task 3.7.x — display-only until then.
  @override
  Future<void> setMute(String ip, bool muted) async {}

  /// Task 3.8.x — display-only until then.
  @override
  Future<void> selectSource(String ip, int statusIndex) async {}
}

final ampCommandSinkProvider = Provider<AmpCommandSink>(
  (ref) => DevialetClientCommandSink(ref.watch(devialetClientProvider)),
);
