import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/amp_state_owner.dart';
import '../../domain/control_view_state.dart';

/// The sheet side of Task 3.8.2's contract: a sheet leaves the navigator
/// as soon as the owner's `visibleSheet` slot stops naming [mine] — an
/// owner-side close (the power edge) or a swap to the other sheet. The
/// current route is popped (animated); a route that is still active but
/// already covered — the Control screen pushed the *other* sheet in the
/// same notification, before this listener ran — is removed in place.
/// Both complete the route's future, so the screen's write-back runs.
/// A route already on its way out (the user popped it and the completion
/// wrote `none` back) is neither current nor active, so it is left alone
/// and the write-back can never double-pop. Call once per build, before
/// any early return.
void popWhenSlotLeaves(WidgetRef ref, BuildContext context, SheetKind mine) {
  ref.listen(controlViewStateProvider.select((s) => s.visibleSheet), (_, next) {
    if (next == mine) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else if (route.isActive) {
      navigator.removeRoute(route);
    }
  });
}
