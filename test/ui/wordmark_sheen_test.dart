import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/ui_variant.dart';
import 'package:devialet_expert_remote_app/ui/control/control_header.dart';
import 'package:devialet_expert_remote_app/ui/control/control_keys.dart';
import 'package:devialet_expert_remote_app/ui/theme/app_tokens.dart';

import 'support/pump_control.dart';

/// Owner request 2026-09-22: the "DEVIALET" wordmark gets the mockups'
/// foil sheen (dark gold on the left → bright on the right), light theme
/// only — the dark theme's copper stays flat, as both v19 mockups have it.
void main() {
  for (final variant in UiVariant.values) {
    testWidgets('light: the wordmark is gradient-masked left-dark → right-bright (${variant.name})', (tester) async {
      await tester.pumpWidget(themed(const ControlHeader(), variant: variant, brightness: Brightness.light));
      expect(find.byKey(ControlKeys.wordmark), findsOneWidget);
      final mask = tester.widget<ShaderMask>(find.byKey(ControlKeys.wordmarkSheen));
      expect(mask.blendMode, BlendMode.srcIn);
      final colors = AppTokens.light.wordmarkGradientColors!;
      expect(colors, const [Color(0xFFA8710B), Color(0xFFD99A1F), Color(0xFFFBE6AB)], reason: 'the mockups\' stops');
      expect(colors.first.computeLuminance(), lessThan(colors.last.computeLuminance()), reason: 'dark left, bright right');
    });

    testWidgets('dark: flat copper, no mask (${variant.name})', (tester) async {
      await tester.pumpWidget(themed(const ControlHeader(), variant: variant, brightness: Brightness.dark));
      expect(find.byKey(ControlKeys.wordmark), findsOneWidget);
      expect(find.byKey(ControlKeys.wordmarkSheen), findsNothing);
      expect(AppTokens.dark.wordmarkGradientColors, isNull);
    });
  }
}
