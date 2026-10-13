import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/ui/platform/adaptive_pressable.dart';

import 'support/pump_control.dart';

/// `AdaptivePressable.overlay` is a second tap target inside the press
/// surface (the device card's power circle). Both variants: a press on the
/// overlay's button never reaches the host — no tap, no press feedback —
/// while the overlay's empty region falls through to the host.
///
/// Red proofs (run once, 2026-09-26): nesting the overlay inside the iOS
/// `GestureDetector` makes the slow-press case scale the host to 0.97 at
/// 150 ms; placing the Android overlay *under* the ink layer turns the
/// overlay tap into a host tap (host 1, overlay 0).
void main() {
  const hostKey = ValueKey('host');
  const buttonKey = ValueKey('button');

  late int hostTaps;
  late int buttonTaps;
  late List<bool> hostPressed;

  Widget host(UiVariant variant) {
    hostTaps = 0;
    buttonTaps = 0;
    hostPressed = [];
    return themed(
      SizedBox(
        height: 80,
        child: AdaptivePressable(
          key: hostKey,
          onTap: () => hostTaps++,
          onPressedChanged: hostPressed.add,
          borderRadius: BorderRadius.circular(18),
          pressedScale: 0.97,
          pressedOpacity: 0.85,
          overlay: Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 17),
              child: AdaptivePressable(
                key: buttonKey,
                onTap: () => buttonTaps++,
                borderRadius: BorderRadius.circular(22),
                builder: (_, _) => const SizedBox(width: 44, height: 44),
              ),
            ),
          ),
          builder: (_, _) => const SizedBox.expand(),
        ),
      ),
      variant: variant,
    );
  }

  for (final variant in UiVariant.values) {
    group(variant.name, () {
      testWidgets('a tap on the overlay button reaches only the button', (tester) async {
        await tester.pumpWidget(host(variant));
        await tester.tap(find.byKey(buttonKey));
        await tester.pump();
        expect((hostTaps, buttonTaps), (0, 1));
        expect(hostPressed, isEmpty, reason: 'the host never saw a press');
      });

      testWidgets('a tap beside the button falls through to the host', (tester) async {
        await tester.pumpWidget(host(variant));
        await tester.tapAt(tester.getTopLeft(find.byKey(hostKey)) + const Offset(20, 40));
        await tester.pump();
        expect((hostTaps, buttonTaps), (1, 0));
        expect(hostPressed, [true, false]);
      });

      testWidgets('a held press on the button shows no host feedback (the 100 ms tap-down deadline)', (tester) async {
        await tester.pumpWidget(host(variant));
        final gesture = await tester.startGesture(tester.getCenter(find.byKey(buttonKey)));
        await tester.pump(const Duration(milliseconds: 150));
        expect(hostPressed, isEmpty);
        if (variant == UiVariant.ios) {
          expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale, 1.0);
        }
        await gesture.up();
        await tester.pump();
        expect((hostTaps, buttonTaps), (0, 1));
      });
    });
  }
}
