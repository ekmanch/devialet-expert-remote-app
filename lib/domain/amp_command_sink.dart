import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../networking/devialet_client.dart';
import 'amp_trace.dart';
import 'devialet_client_provider.dart';
import 'settings/settings_owner.dart';

/// Where the owner's intents send commands. The owner writes its
/// optimistic value *before* calling this and rolls that value back if the
/// call throws (checklist item 3; `docs/protocol.md`, reconciliation #6).
///
/// The default is [DevialetClientCommandSink]. Power and the post-boot
/// startup volume have been real since Task 3.2.x; user volume and mute
/// since Tasks 3.6.0 / 3.7.0 (2026-09-22). Source selection stays
/// display-only until Task 3.8 flips it.
abstract interface class AmpCommandSink {
  /// A volume the user asked for, or the limit clamp's correction (Task
  /// 3.6.6) — same opcode as [sendStartupVolume]. Never unmutes by itself:
  /// the owner sends [setMute] first when a *user* change should unmute
  /// (Task 3.6.5); corrections don't (Task 3.7.1).
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
  DevialetClientCommandSink(this._client, {required this.ceilingDb, this.trace = AmpTrace.none});

  final DevialetClient _client;

  /// Debug trace of every *real* send, emitted before the await so the
  /// timestamp is the send instant (Task 3.5.2). The one remaining
  /// display-only stub (`selectSource`) traces nothing until 3.8 flips it.
  final AmpTrace trace;

  /// The wire-side ceiling, read at send time so a Settings change applies
  /// to the next command (Task 3.4.7 / 1.1.3). `null` would mean unbounded;
  /// the app never passes that.
  final double? Function() ceilingDb;

  @override
  Future<void> setPower(String ip, bool on) {
    trace('send power', {'ip': ip, 'on': on});
    _client.deviceIp = ip;
    return _client.setPower(on);
  }

  /// The settings ceiling is a second, wire-side clamp on top of
  /// `AmpState.startupVolumeTarget`'s (gotcha #6, defence in depth).
  @override
  Future<void> sendStartupVolume(String ip, double db) {
    final ceiling = ceilingDb();
    trace('send startupVolume', {'ip': ip, 'db': db, 'ceiling': ceiling});
    _client.deviceIp = ip;
    return _client.setVolumeDb(db, maxDb: ceiling);
  }

  /// Task 3.6.0: the same wire-side ceiling as the startup send (gotcha #6;
  /// the owner already clamped to the floor/ceiling, this is the required
  /// parameter's defence in depth).
  @override
  Future<void> setVolumeDb(String ip, double db) {
    final ceiling = ceilingDb();
    trace('send volume', {'ip': ip, 'db': db, 'ceiling': ceiling});
    _client.deviceIp = ip;
    return _client.setVolumeDb(db, maxDb: ceiling);
  }

  /// Task 3.7.0.
  @override
  Future<void> setMute(String ip, bool muted) {
    trace('send mute', {'ip': ip, 'muted': muted});
    _client.deviceIp = ip;
    return _client.setMute(muted);
  }

  /// Task 3.8.x — display-only until then.
  @override
  Future<void> selectSource(String ip, int statusIndex) async {}
}

final ampCommandSinkProvider = Provider<AmpCommandSink>(
  (ref) => DevialetClientCommandSink(
    ref.watch(devialetClientProvider),
    ceilingDb: () => ref.read(settingsProvider).ceilingDb,
    trace: ref.watch(ampTraceProvider),
  ),
);
