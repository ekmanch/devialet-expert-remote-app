import 'dart:async';

import 'package:devialet_expert_remote_app/domain/monotonic_clock.dart';

/// Deterministic clock: tests move time explicitly.
class FakeClock implements MonotonicClock {
  FakeClock([Duration start = Duration.zero]) : _now = start;

  Duration _now;

  @override
  Duration now() => _now;

  void advance(Duration by) => _now += by;

  void set(Duration to) => _now = to;
}

/// Stand-in for the 1 s stale tick: fires only when a test says so.
class ManualTicker {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get stream => _controller.stream;

  void tick() => _controller.add(null);

  Future<void> close() => _controller.close();
}
