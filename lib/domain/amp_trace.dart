import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'monotonic_clock.dart';

typedef TraceEmit = void Function(String line);

/// Debug-only narration of what the owner saw, decided and sent, one line
/// per event on the owner's monotonic clock — the "raw source of truth
/// next to the app" a live verification needs (checklist item 22; Task
/// 3.5.2 reads it over `adb logcat`).
///
/// Format: `[amp] <ms>ms <event> k=v k=v`. Events (see
/// `docs/architecture.md`, "Debug trace"):
///
/// - `send power` / `send startupVolume` — a real send, emitted *before* the
///   await, from the one sink method each real command passes through;
/// - `send failed` — the sink threw (a dead route, not a dropped packet);
/// - `rx` — the selected amp's broadcast, only when power or the raw
///   volume byte changed (change-only, so `debugPrint` throttling never bites);
/// - `boot booting` / `boot confirmed` / `boot observed-external` /
///   `boot timeout` / `boot startup-send` — the boot machine;
/// - `hold released reason=confirmed|fallback` — the post-boot display hold;
/// - `view` — the *displayed* power / volume / mute / hasAmp changed: what
///   the dial showed, from the same derivation the UI renders.
///
/// The default is [none]: `lib/domain/` has no Flutter import, so the
/// `debugPrint` emitter is injected by `main.dart` under `kDebugMode` and
/// release builds trace nothing. Every call site checks [enabled] before
/// doing any diffing work.
class AmpTrace {
  const AmpTrace(TraceEmit emit, MonotonicClock clock) : _emit = emit, _clock = clock;

  const AmpTrace._none() : _emit = null, _clock = null;

  static const AmpTrace none = AmpTrace._none();

  final TraceEmit? _emit;
  final MonotonicClock? _clock;

  bool get enabled => _emit != null;

  void call(String event, [Map<String, Object?> fields = const {}]) {
    final emit = _emit;
    if (emit == null) return;
    emit(format(_clock!.now(), event, fields));
  }

  static String format(Duration at, String event, [Map<String, Object?> fields = const {}]) {
    final buffer = StringBuffer('[amp] ${at.inMilliseconds}ms $event');
    for (final entry in fields.entries) {
      buffer.write(' ${entry.key}=${entry.value}');
    }
    return buffer.toString();
  }
}

/// Off by default; `main.dart` overrides it in debug builds, tests
/// override it with a capturing emitter.
final ampTraceProvider = Provider<AmpTrace>((_) => AmpTrace.none);
