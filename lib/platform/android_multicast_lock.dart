import 'package:flutter/services.dart';

import '../networking/model_name_source.dart';

/// `WifiManager.MulticastLock` over a `MethodChannel` (Task 3.9.5). Android
/// (Samsung in particular) filters multicast off the Wi-Fi radio while no
/// app holds the lock, which is what the Kotlin app's `NsdManager` restart
/// bursts were working around; `multicast_dns` needs the packets to
/// arrive. Held only for a browse session (`MulticastDnsModelNameSource`).
///
/// Errors (`MissingPluginException`, `PlatformException`) propagate: the
/// source turns them into its one terminal error, so a broken lock looks
/// broken (checklist 26) instead of silently browsing without it.
class AndroidMulticastLock implements MulticastLock {
  const AndroidMulticastLock();

  static const MethodChannel channel = MethodChannel('com.ekmanch.devialet_expert_remote_app/multicast_lock');

  @override
  Future<void> acquire() => channel.invokeMethod<void>('acquire');

  @override
  Future<void> release() => channel.invokeMethod<void>('release');
}
