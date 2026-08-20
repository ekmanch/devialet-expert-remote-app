import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/ui_variant.dart';
import 'debug/debug_network_screen.dart';

/// Phase 1 root widget: no real feature screens yet, just the debug
/// networking scaffold — but routed through [uiVariantProvider] so the
/// Android/iOS shell switch is already wired end-to-end for later phases.
class DevialetRemoteApp extends ConsumerWidget {
  const DevialetRemoteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variant = ref.watch(uiVariantProvider);
    final home = DebugNetworkScreen(variant: variant);

    if (variant == UiVariant.ios) {
      return CupertinoApp(debugShowCheckedModeBanner: false, home: home);
    }
    return MaterialApp(debugShowCheckedModeBanner: false, home: home);
  }
}
