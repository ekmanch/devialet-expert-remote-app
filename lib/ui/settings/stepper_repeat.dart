import 'dart:async';

/// Settings-stepper hold-to-repeat timings, **from the v19 mockup's JS and
/// unmeasured** (TODO 3.4.3, checklist item 14): the Galaxy S25 check
/// records the feel and any change. One step fires at once on press; after
/// [kStepperHoldDelay] the repeat interval is installed at
/// [kStepperRepeatStart] (so the first repeat lands at 420 + 140 = 560 ms,
/// as the mockup's `setInterval`) and shortens by [kStepperRepeatAccel] per
/// tick down to [kStepperRepeatFloor]:
/// 0, 560, 688, 804, 908, 1000, 1080, 1148, 1204, then every 45 ms.
const Duration kStepperHoldDelay = Duration(milliseconds: 420);
const Duration kStepperRepeatStart = Duration(milliseconds: 140);
const Duration kStepperRepeatAccel = Duration(milliseconds: 12);
const Duration kStepperRepeatFloor = Duration(milliseconds: 45);

/// Press → first repeat for the settings stepper (420 + 140 = 560 ms).
const Duration kStepperFirstRepeatAt = Duration(milliseconds: 560);

/// The timer chain behind a press-and-hold button. [onTick] performs one
/// step and returns false when it could not move (at a bound), which ends
/// the chain — a hold at the limit does nothing rather than flashing.
///
/// Schedule: one tick at `start()`, the next [firstRepeatAt] after it,
/// then every [interval], shortened by [accel] per tick down to [floor]
/// (`accel == Duration.zero` gives a flat repeat, as the VOL ± buttons
/// use — Task 3.6.1: 300 ms, then every 100 ms, Qt `autoRepeat` semantics).
/// The defaults are the settings stepper's: its first repeat lands at
/// hold delay + first interval, as the mockup's `setInterval` did.
class StepperRepeatController {
  StepperRepeatController({
    required this.onTick,
    this.firstRepeatAt = kStepperFirstRepeatAt,
    this.interval = kStepperRepeatStart,
    this.accel = kStepperRepeatAccel,
    this.floor = kStepperRepeatFloor,
  });

  final bool Function() onTick;
  final Duration firstRepeatAt;
  final Duration interval;
  final Duration accel;
  final Duration floor;
  Timer? _timer;
  late Duration _interval = interval;

  bool get isActive => _timer != null;

  void start() {
    stop();
    if (!onTick()) return;
    _interval = interval;
    _timer = Timer(firstRepeatAt, _repeatTick);
  }

  void _repeatTick() {
    _timer = null;
    if (!onTick()) return;
    final next = _interval - accel;
    _interval = next < floor ? floor : next;
    _timer = Timer(_interval, _repeatTick);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
