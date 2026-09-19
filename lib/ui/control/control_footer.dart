import 'package:flutter/widgets.dart';

import '../../domain/control_view_state.dart';
import '../theme/app_theme.dart';
import 'control_keys.dart';

/// Static status word (TODO 2.0.10; owner decision 2026-09-19: a silent
/// amp reads "Not connected", there is no third word).
class ControlFooter extends StatelessWidget {
  const ControlFooter({super.key, required this.state});

  final ControlViewState state;

  static String textFor(ControlViewState s) => s.hasAmp ? 'Connected' : 'Not connected';

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Text(
        textFor(state),
        key: ControlKeys.footer,
        textAlign: TextAlign.center,
        style: theme.type.mono(size: 11, letterSpacingEm: 0.02, color: theme.tokens.textFaint),
      ),
    );
  }
}
