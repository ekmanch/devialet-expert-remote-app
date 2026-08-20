# App Overview

Based on commit `743aa71` (current `main`, working tree clean). Android-only
app today — this doc exists to inform the Flutter/iOS+Android port, so the
platform-specific section below is written with that in mind, not as a
Android-only afterthought.

## Architecture

Single-Activity app, no navigation framework, no ViewModel/MVVM layer, no DI
framework. All UI state lives directly as fields on `MainActivity`. Small,
deliberately simple codebase (~1,780 lines across 7 Kotlin files, no test suite).

```
MainActivity (UI + all app state)
 ├─ DevialetController      — builds/sends UDP command packets (fire-and-forget)
 ├─ DevialetStatusListener  — background thread, passively receives amp status broadcasts
 ├─ AmpModelNameResolver    — mDNS (NSD) lookup for a nicer "make/model" display name
 ├─ DevialetStatus / DevialetSource  — plain data classes, parsed status snapshot
 ├─ DiscoveredAmp           — plain data class, one entry in the LAN amp list
 └─ VolumeDialView          — custom View, the draggable circular volume control
```

- **`MainActivity`** owns: all view references (manual `findViewById`, no
  ViewBinding/Compose), the currently-selected amp, the in-memory map of every
  amp heard on the LAN (`discoveredAmps: LinkedHashMap<String, DiscoveredAmp>`),
  local-only UI state for not-yet-wired features (SAM/Night Mode/Bass/Treble),
  and all the debounce timers described in `docs/known-gotchas.md`.
- **`DevialetController`** is effectively stateless aside from holding the
  target `deviceIp` (`@Volatile var`, mutated when the user picks a different
  amp). No persistent socket — opens/closes a fresh `DatagramSocket` per
  command. See `docs/protocol.md` for wire details.
- **`DevialetStatusListener`** runs its own daemon `Thread` with a blocking
  `DatagramSocket.receive()` loop, started in `onResume()` and stopped in
  `onPause()`. Its callback fires on that background thread; `MainActivity`
  wraps it in `runOnUiThread {}` — the listener class itself has no Android UI
  thread awareness.
- **Threading model:** one single-thread `ExecutorService` (`network`) for all
  outbound commands (`network.submit { runCatching { controller.xxx() } }`),
  one daemon thread for inbound status, plus a handful of `Handler(Looper.getMainLooper())`
  instances for timed UI work (debounce windows, picker refresh, card refresh,
  volume repeat-while-held). No coroutines, no RxJava, no WorkManager.
- **No dependency injection** — everything is constructed directly in
  `MainActivity.onCreate()`.

## Core features and user flows

1. **Amp discovery & selection** — the app never asks the user to type an IP
   up front. It passively listens for every amp's UDP status broadcast on the
   LAN and builds a live list (`discoveredAmps`), keyed by sender IP. Tapping
   the device card at the top opens a bottom sheet (`showAmpSheet()`) listing:
   - an explicit **"None"** row (disconnects — distinct from simply never
     having picked an amp, though both end up at the same "no amp selected"
     state),
   - every amp heard from in the last 8s (`ampStaleTimeoutMs`), refreshed live
     once/sec while the sheet is open,
   - a manual-IP-entry fallback folded into the same sheet (for different
     subnet/VLAN cases where broadcast discovery can't reach the amp).
   Selection is persisted (see below) and immediately starts a fast mDNS
   re-resolve burst for the model name if not already known.
2. **Control tab** — power on/off, mute/unmute, a draggable circular volume
   dial (`VolumeDialView`, custom-drawn, mirrors the amp's physical knob) plus
   VOL -/+ buttons with tap-for-single-step and press-and-hold-to-repeat
   (0.5dB/step, 5dB/sec while held), and a source picker (bottom sheet, live
   source list from the amp's own status broadcast).
3. **Sound tab** — SAM on/off + level (0-100%), Night Mode on/off, Bass/Treble
   (-18..+18dB). **All of this is local-UI-state only** — none of it sends
   anything to the amp yet (see `docs/protocol.md`, "Known-unimplemented
   commands"). Both tabs dim/disable when no amp is selected, with dedicated
   empty states rather than just looking broken.
4. **Live status reflection** — every incoming status broadcast (from *any*
   amp on the LAN) updates the discovery list; only broadcasts from the
   currently-selected amp's IP update the live volume/mute/power/source
   display, with debounce windows to avoid visibly fighting the user's own
   in-flight changes (see `docs/known-gotchas.md` #1-#2).
5. **Model name resolution** — cosmetic enhancement: resolves the amp's real
   make/model (e.g. "Devialet Expert 140 Pro") via mDNS against the
   `_spotify-connect._tcp.` service type, falling back to the amp's own
   UDP-broadcast "friendly name" (e.g. "My Devialet-ETH") when unresolved or
   unavailable. Android 16 (API 36) minimum for this feature specifically —
   silently no-ops below that OS version.

## Persisted state

Only **`SharedPreferences`**, file name `"devialet_remote"`, `MODE_PRIVATE`.
Two keys, both `String`:

| Key | Meaning | Written from |
|---|---|---|
| `amp_ip` | Last-selected amp's IP address | `MainActivity.selectAmp()` / `clearAmpSelection()` |
| `amp_name` | Last-selected amp's friendly (UDP-broadcast) name | same |

That's the entire persistence footprint. Notably **not persisted**:
- The list of amps ever discovered on the LAN (`discoveredAmps` is rebuilt
  from scratch every app launch, purely from live broadcasts).
- The resolved model name (`DiscoveredAmp.modelName`) — re-resolved via mDNS
  every launch.
- Every "local-only" Sound tab value (SAM level, Bass, Treble, SAM/Night Mode
  on-off) — resets to hardcoded defaults (`samLevel = 70`, `bassDb = 0`,
  `trebleDb = 0`, `samOn = true`, `nightOn = false`) on every fresh process
  start, since none of it is wired to the amp or saved locally.
- No database, no file-based cache, no cloud sync of any kind (by design —
  this is explicitly a no-cloud, LAN-only app).

## Third-party dependencies (functional, not build tooling)

| Dependency | Purpose | Notes |
|---|---|---|
| `com.google.android.material:material` | `BottomSheetDialog` only | Explicitly scoped down in a build-file comment: "Only used for BottomSheetDialog (source picker) - native drag-to-dismiss and edge-to-edge handling instead of the hand-rolled Dialog+scrim it replaced." Both bottom sheets (amp picker, source picker) depend on this. |
| `androidx.appcompat` | `AppCompatActivity`, `SwitchCompat` | Standard Android base; no functional networking role. |
| `androidx.core-ktx` | `SharedPreferences.edit {}` KTX helper, `ContextCompat` | Convenience only. |

No networking libraries (no OkHttp/Retrofit/Ktor) — all UDP socket code is
hand-rolled `java.net.DatagramSocket`/`DatagramPacket`. No JSON/serialization
library — the protocol is raw fixed-offset binary, parsed by hand.
No image loading, no analytics, no crash reporting SDKs present.

## Platform-specific behavior — needs an explicit iOS/Flutter equivalent

This app currently has **no background service, no notifications, and no
special lifecycle handling beyond stopping network activity when backgrounded** —
which is simpler than a typical Android app, but every one of these choices
was made implicitly by relying on Android-specific APIs, so each needs a
deliberate decision (not just a 1:1 translation) for iOS:

- **UDP status listening is tied to foreground lifecycle, Android-style.**
  `DevialetStatusListener.start()`/`.stop()` are called from `onResume()`/`onPause()`
  — i.e. the socket is only open while the Activity is in the foreground.
  There is **no background service, no foreground-service notification, no
  WorkManager** keeping the socket alive when backgrounded. On iOS, background
  UDP socket behavior is far more restricted than Android (sockets are
  generally suspended within seconds of backgrounding, with no
  general-purpose "background networking" entitlement analogous to a plain
  Android background thread) — this needs a real design decision, not an
  assumption that "it'll just work the same." At minimum, expect the iOS
  version to lose live status updates while backgrounded even more
  aggressively than Android already does today.
- **mDNS discovery (`AmpModelNameResolver`) is built entirely on Android's
  `NsdManager`**, including an Android-specific workaround: it restarts
  discovery sessions on its own schedule (`RETRY_DELAYS_MS`/`STEADY_INTERVAL_MS`)
  to compensate for Android's mDNS backoff and "some OEM Wi-Fi stacks"
  (explicitly calls out Samsung) being slow in power-save states. iOS has its
  own native mDNS/Bonjour APIs (`NWBrowser`/`NetServiceBrowser`) with different
  timing/backoff characteristics — the retry-burst tuning here is
  Android-specific and should not be assumed to carry over as-is.
  Also gated to **API 36+ only** on Android (`NsdServiceInfo.getHostname()`),
  silently doing nothing below that — the Flutter port needs its own
  version/capability gating per platform, not a shared assumption.
- **Permissions:** only install-time (non-runtime-prompted) Android
  permissions are declared — `INTERNET`, `ACCESS_WIFI_STATE`,
  `ACCESS_NETWORK_STATE`. No runtime permission dialogs exist in this app
  today. iOS, however, gates **local network access** (which this app
  fundamentally depends on — LAN UDP broadcast/unicast) behind a user-facing
  runtime permission prompt (`NSLocalNetworkUsageDescription` +, if using
  Bonjour/mDNS for discovery, an `NSBonjourServices` entry) with no Android
  equivalent in this codebase to model the flow after. This is a **new
  runtime permission flow** the Flutter port must design from scratch for iOS
  — including handling "denied" and "not yet asked" states, which this app
  currently has zero code paths for.
- **Cleartext traffic:** `android:usesCleartextTraffic="true"` is explicitly
  set (required since the whole protocol is plaintext UDP, no TLS). iOS's App
  Transport Security (ATS) has its own separate cleartext/local-network
  exception mechanism (`NSAppTransportSecurity` / `NSExceptionDomains` or the
  `NSAllowsLocalNetworking` key) that isn't automatically implied by the
  Android manifest flag — needs its own explicit `Info.plist` configuration.
- **No notifications of any kind** exist in the current app (no status-change
  notifications, no foreground-service notification) — nothing to port
  directly, but worth confirming this is still the desired scope for the
  Flutter version rather than assuming parity means "add what's missing."
- **Storage:** `SharedPreferences` is Android-only; the two persisted string
  keys (`amp_ip`, `amp_name`) map cleanly to `shared_preferences` (Flutter
  plugin) or platform-native equivalents (`UserDefaults` on iOS) — this one is
  low-risk, called out mainly for completeness since everything else in this
  section is not low-risk.
- **`SystemClock.elapsedRealtime()`** is used throughout for all timing/debounce
  logic (staleness checks, debounce windows, picker refresh) specifically
  *because* it's monotonic and immune to wall-clock adjustments — the Flutter
  port needs an equivalent monotonic clock source (e.g. Dart's
  `Stopwatch`/`DateTime` has its own platform nuances) rather than naively
  reaching for wall-clock time, or the debounce fixes in
  `docs/known-gotchas.md` could silently regress.
- **Screen/orientation handling:** `android:configChanges="orientation|screenSize"`
  means `MainActivity` handles rotation itself rather than being
  recreated — there is no separate state-restoration path
  (`onSaveInstanceState`) being exercised in practice. Flutter's widget
  rebuild model is different enough that this specific Android mechanism
  doesn't map 1:1; flagging so state-preservation-across-rotation isn't
  silently dropped when porting.

## Not currently platform-specific (safe to treat as shared logic)

For contrast — these are safe to port as pure Dart/shared logic without a
per-platform variant, since nothing about them depends on Android APIs:

- All UDP packet construction/parsing (`DevialetController`,
  `DevialetStatusListener.parseStatus()`) — pure byte manipulation, no
  Android dependency beyond `java.net.DatagramSocket`/`DatagramPacket`, which
  Dart's `dart:io` `RawDatagramSocket` covers on both platforms.
  ⚠️ Note the mismatch though: `DevialetStatusListener`'s *lifecycle* (when
  the socket opens/closes) is Android-lifecycle-driven per the section above,
  even though the parsing logic itself isn't.
- CRC16, dB↔byte conversion (`dbConvert`), source index remapping table — all
  pure math/data, no platform dependency.
- Debounce timing *logic* (the windows/thresholds themselves) — the numbers
  should port directly; only the underlying clock primitive changes per
  platform note above.
