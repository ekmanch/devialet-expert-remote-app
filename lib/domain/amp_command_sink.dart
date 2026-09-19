import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the owner's intents send commands. The owner writes its
/// optimistic value *before* calling this and rolls that value back if the
/// call throws (checklist item 3; `docs/protocol.md`, reconciliation #6).
///
/// Task 3.0.x ships [NoopCommandSink]: intents are display-only, so an
/// optimistic value reverts after the pending window unless the amp
/// happens to agree. Tasks 3.5–3.9 replace the provider body with a
/// `DevialetClient`-backed sink — a one-line swap.
abstract interface class AmpCommandSink {
  Future<void> setVolumeDb(String ip, double db);
  Future<void> setMute(String ip, bool muted);
  Future<void> setPower(String ip, bool on);
  Future<void> selectSource(String ip, int statusIndex);
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
}

final ampCommandSinkProvider = Provider<AmpCommandSink>((_) => const NoopCommandSink());
