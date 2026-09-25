import 'package:flutter/services.dart';

import '../networking/model_name_source.dart';

/// `_spotify-connect._tcp` over the iOS Bonjour APIs (Task 3.9.5), an
/// `EventChannel` fed by `ios/Runner/BonjourModelNameStreamHandler.swift`
/// (`NetServiceBrowser` → `NetService.resolve` → `hostName` + first IPv4).
/// Bonjour goes through the system's mDNS responder and needs no
/// multicast entitlement — pure-Dart `multicast_dns` would, on iOS 14+.
/// Needs `NSBonjourServices` and `NSLocalNetworkUsageDescription` in
/// `Info.plist`; the permission *flow* is Task 4.0.0.
///
/// Subscribing starts the browser, cancelling stops it; a platform error
/// (`didNotSearch`: the plist entry missing, local network denied) is the
/// one terminal stream error the [ModelNameSource] contract describes.
///
/// **Unverified on a device until the iPad session (Task 4.0.x).**
class BonjourModelNameSource implements ModelNameSource {
  const BonjourModelNameSource();

  static const EventChannel channel = EventChannel('com.ekmanch.devialet_expert_remote_app/bonjour_model_names');

  @override
  Stream<ModelNameHit> browse() => channel.receiveBroadcastStream().map((event) {
    final map = event as Map<Object?, Object?>;
    return (hostname: map['host']! as String, ip: map['ip']! as String);
  });
}
