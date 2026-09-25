import Flutter
import Foundation

/// Task 3.9.5: browses `_spotify-connect._tcp.` and streams
/// `{"host": <SRV host name>, "ip": <first IPv4>}` events to
/// `BonjourModelNameSource` (Dart). Bonjour goes through the system's
/// mDNS responder, so no multicast entitlement is needed — only the
/// `NSBonjourServices` / `NSLocalNetworkUsageDescription` keys in
/// Info.plist.
///
/// `NetServiceBrowser` is deprecated since iOS 15 but is the only API that
/// returns the SRV `hostName` directly (`NWBrowser` yields endpoints, not
/// the host); migrate to `NWBrowser` + a manual SRV resolve if Apple
/// removes it. A failed search (`didNotSearch`: missing plist entry, local
/// network denied) is reported as the one terminal error the Dart contract
/// describes; the permission *flow* is Task 4.0.0.
///
/// Unverified on a device until the iPad session (Task 4.0.x).
final class BonjourModelNameStreamHandler: NSObject, FlutterStreamHandler, NetServiceBrowserDelegate, NetServiceDelegate {
  private var browser: NetServiceBrowser?
  /// Strong references while resolving; `NetService` is not retained by its browser.
  private var pending = Set<NetService>()
  private var sink: FlutterEventSink?

  func onListen(withArguments _: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    sink = eventSink
    let browser = NetServiceBrowser()
    browser.delegate = self
    self.browser = browser
    browser.searchForServices(ofType: "_spotify-connect._tcp.", inDomain: "local.")
    return nil
  }

  func onCancel(withArguments _: Any?) -> FlutterError? {
    browser?.stop()
    browser = nil
    pending.forEach { $0.stop() }
    pending.removeAll()
    sink = nil
    return nil
  }

  // MARK: NetServiceBrowserDelegate

  func netServiceBrowser(_: NetServiceBrowser, didFind service: NetService, moreComing _: Bool) {
    pending.insert(service)
    service.delegate = self
    service.resolve(withTimeout: 5)
  }

  func netServiceBrowser(_: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
    sink?(FlutterError(code: "browse", message: "Bonjour search failed: \(errorDict)", details: nil))
    sink?(FlutterEndOfEventStream)
  }

  // MARK: NetServiceDelegate

  func netServiceDidResolveAddress(_ service: NetService) {
    defer { pending.remove(service) }
    guard let host = service.hostName,
          let ip = service.addresses?.lazy.compactMap(Self.ipv4).first
    else { return }
    sink?(["host": host, "ip": ip])
  }

  func netService(_ service: NetService, didNotResolve _: [String: NSNumber]) {
    pending.remove(service)
  }

  /// The dotted quad of an `AF_INET` socket address, or nil for anything else.
  private static func ipv4(_ data: Data) -> String? {
    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> String? in
      guard let base = raw.baseAddress, raw.count >= MemoryLayout<sockaddr_in>.size else { return nil }
      let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
      guard family == sa_family_t(AF_INET) else { return nil }
      var address = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
      var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
      guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
      return String(cString: buffer)
    }
  }
}
