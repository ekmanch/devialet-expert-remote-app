import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Every owner-side timer (staleness, pending-command deadlines, the boot
/// deadline) is expressed as a `Duration` on one monotonic clock — never
/// wall-clock time (`docs/protocol.md`, "Timing facts"). Injectable so
/// tests advance time deterministically.
abstract interface class MonotonicClock {
  Duration now();
}

class StopwatchClock implements MonotonicClock {
  final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  Duration now() => _stopwatch.elapsed;
}

final monotonicClockProvider = Provider<MonotonicClock>((_) => StopwatchClock());

/// The 1 s tick on which staleness and expired pending deadlines are
/// re-evaluated when no broadcast arrives (KDE daemon `POLL_TICK`). There
/// are no per-field timers: deadlines are compared against the clock on
/// every ingest and on this tick.
final staleTickProvider = Provider<Stream<void>>(
  (_) => Stream<void>.periodic(const Duration(seconds: 1)),
);
