import 'dart:async';

/// Hold-to-repeat timings, **from the v19 mockup's JS and unmeasured**
/// (TODO 3.4.3, checklist item 14): the Galaxy S25 check records the feel
/// and any change. One step fires at once on press; after [kStepperHoldDelay]
/// the repeat interval is installed at [kStepperRepeatStart] (so the first
/// repeat lands at 420 + 140 = 560 ms, as the mockup's `setInterval`) and
/// shortens by [kStepperRepeatAccel] per tick down to [kStepperRepeatFloor]:
/// 0, 560, 688, 804, 908, 1000, 1080, 1148, 1204, then every 45 ms.
const Duration kStepperHoldDelay = Duration(milliseconds: 420);
const Duration kStepperRepeatStart = Duration(milliseconds: 140);
const Duration kStepperRepeatAccel = Duration(milliseconds: 12);
const Duration kStepperRepeatFloor = Duration(milliseconds: 45);

/// The timer chain behind a stepper button. [onTick] performs one step
/// and returns false when it could not move (at a bound), which ends the
/// chain — a hold at the limit does nothing rather than flashing.
class StepperRepeatController {
  StepperRepeatController({required this.onTick});

  final bool Function() onTick;
  Timer? _timer;
  Duration _interval = kStepperRepeatStart;

  bool get isActive => _timer != null;

  void start() {
    stop();
    if (!onTick()) return;
    _interval = kStepperRepeatStart;
    _timer = Timer(kStepperHoldDelay + _interval, _repeatTick);
  }

  void _repeatTick() {
    _timer = null;
    if (!onTick()) return;
    final next = _interval - kStepperRepeatAccel;
    _interval = next < kStepperRepeatFloor ? kStepperRepeatFloor : next;
    _timer = Timer(_interval, _repeatTick);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
