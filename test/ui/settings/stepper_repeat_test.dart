import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/settings/stepper_repeat.dart';

void main() {
  testWidgets('tick schedule: 0, 560, 688, 804, 908, 1000 … then every 45 ms', (tester) async {
    var ticks = 0;
    final c = StepperRepeatController(onTick: () {
      ticks++;
      return true;
    });
    c.start();
    expect(ticks, 1);
    await tester.pump(const Duration(milliseconds: 559));
    expect(ticks, 1, reason: 'hold delay 420 + first interval 140');
    await tester.pump(const Duration(milliseconds: 1));
    expect(ticks, 2);
    for (final gap in [128, 116, 104, 92, 80, 68, 56, 45, 45, 45]) {
      await tester.pump(Duration(milliseconds: gap - 1));
      final before = ticks;
      await tester.pump(const Duration(milliseconds: 1));
      expect(ticks, before + 1, reason: 'gap $gap');
    }
    c.dispose();
  });

  testWidgets('a tick that cannot move ends the chain; stop() before the delay leaves exactly one tick', (tester) async {
    var ticks = 0;
    final blocked = StepperRepeatController(onTick: () {
      ticks++;
      return false;
    });
    blocked.start();
    await tester.pump(const Duration(seconds: 2));
    expect(ticks, 1);
    expect(blocked.isActive, isFalse);

    ticks = 0;
    final c = StepperRepeatController(onTick: () {
      ticks++;
      return true;
    });
    c.start();
    await tester.pump(const Duration(milliseconds: 200));
    c.stop();
    await tester.pump(const Duration(seconds: 2));
    expect(ticks, 1);
    c.dispose();
  });

  testWidgets('a flat schedule (accel zero): 0, firstRepeatAt, then every interval (VOL ± use 300/100)', (
    tester,
  ) async {
    var ticks = 0;
    final c = StepperRepeatController(
      onTick: () {
        ticks++;
        return true;
      },
      firstRepeatAt: const Duration(milliseconds: 300),
      interval: const Duration(milliseconds: 100),
      accel: Duration.zero,
    );
    c.start();
    expect(ticks, 1);
    await tester.pump(const Duration(milliseconds: 299));
    expect(ticks, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(ticks, 2);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 99));
      expect(ticks, 2 + i);
      await tester.pump(const Duration(milliseconds: 1));
      expect(ticks, 3 + i);
    }
    c.dispose();
  });
}
