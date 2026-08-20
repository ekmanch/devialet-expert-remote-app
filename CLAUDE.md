# CLAUDE.md

## Project

Flutter remote-control app for the Devialet Expert Pro 140 amplifier, targeting
both Android and iOS. This is a port of an earlier Android-only Kotlin app
(source of truth for protocol and known bugs — see `docs/`).

## Background

A pure Android app was developed earlier in Kotlin. The repo where all of the
code can be accessed is this one:
https://github.com/ekmanch/devialet-expert-remote
Please refer to it for hints on how things may be implemented. The code in
this repo has been tested on target (Samsung Galaxy S25) with great results.
UDP communication works well. mDNS resolution of model and make works great.
UI elements look good and behave as expected.

For day-to-day reference, prefer docs/protocol.md, docs/known-gotchas.md,
and docs/app-overview.md (generated from this repo) over fetching the repo
directly — only go to the repo link itself if you need to verify something
those docs don't cover or flagged as uncertain. Don't assume the Kotlin repo
is checked out locally; it's a separate repo from this one, accessible only
via that URL.

## Reference docs (read before working on networking or porting features)

- `docs/protocol.md` — UDP packet structure, transport details, command types.
  Treat this as the spec for the networking layer. Anything marked
  "inferred, not confirmed" should be verified against real device traffic
  before being relied on.
- `docs/known-gotchas.md` — bugs already found and fixed in the Kotlin app.
  Check this before implementing anything networking/state related so we
  don't reintroduce a fixed bug.
- `docs/app-overview.md` — architecture and feature overview of the original
  app, including a section on Android-specific behavior that needs an
  iOS-equivalent design decision in Flutter.
- `TODO.md` — tracks deferred work (features, bugs, UI updates, pending
  protocol verification). Check before starting new work in case it's
  already listed; update it (check off completed items, add newly
  discovered ones) as part of your work rather than leaving it stale.

## Platforms

- Targets: Android and iOS, both first-class.
- UI intentionally diverges by platform: Material conventions on Android,
  more iOS-native conventions (navigation, back behavior, settings layout)
  on iOS. Don't default to a single shared UI "that looks fine on both" —
  check which platform's conventions apply per screen.
- Primary dev/test device: Samsung Galaxy S25, via Android Studio. iOS
  builds/testing happen less frequently, so the app must support previewing
  the iOS UI variant while running on Android — see "Runtime UI variant"
  below. Don't assume a physical iOS device is available for quick iteration.

## Runtime UI variant switching

Debug-only mechanism to force which platform's UI renders, independent of the
actual OS — implemented in `lib/config/ui_variant.dart`.

- `UiVariant` enum (`android` / `ios`), exposed via the `uiVariantProvider`
  Riverpod provider (`lib/config/ui_variant.dart`).
- Controlled by a `--dart-define=UI_VARIANT=android` or
  `--dart-define=UI_VARIANT=ios` launch argument, read via
  `String.fromEnvironment('UI_VARIANT')`. Omit the define (or pass anything
  else) to fall back to the real OS via `defaultTargetPlatform`.
- Gated behind `kDebugMode` — the override is ignored entirely in release
  builds even if the define somehow leaks into one.
- **Android Studio run configuration:** Run → Edit Configurations → select
  the Flutter run config → "Additional run args" field → add
  `--dart-define=UI_VARIANT=ios` (or `=android`). Duplicate the run config
  once per variant (e.g. "Galaxy S25 (Android UI)" / "Galaxy S25 (iOS UI
  preview)") so switching is a one-click launch-config change, no rebuild of
  tooling required — this is what lets the iOS UI variant be previewed while
  running on the Galaxy S25.

When adding a new screen or widget with platform-specific styling, route the
platform check through `uiVariantProvider` rather than `Platform.isIOS` /
`Theme.of(context).platform` directly, so it stays overridable.

## Networking

- Core protocol logic (packet encode/decode, socket handling) should be
  isolated from UI/state layers and unit-testable without a real device.
- Follow `docs/protocol.md` exactly for packet structure — don't
  reconstruct it from guesswork even if it "looks similar" to a common
  pattern.
- Cross-check any new networking code against `docs/known-gotchas.md`.

## Working style

- This is a phased port (scaffold+networking → domain/state → Android UI →
  iOS UI → polish). Don't jump ahead to UI work before the networking layer
  is verified against the real amp.
- Prefer flagging ambiguity over guessing, especially for protocol/state
  behavior — ask rather than assume if `docs/` doesn't cover it.
- Keep commits scoped to one phase/concern at a time.

## Environment

- IDE: Android Studio (Flutter/Dart plugins).
- Package manager / tooling: Flutter's built-in `pub` (`flutter pub`/`dart
  pub`) — no separate package manager. Flutter 3.47.0 (stable channel), Dart
  SDK constraint `^3.13.0` in `pubspec.yaml` (matches the version installed
  on the primary dev machine at scaffold time). No FVM/version-pinning tool
  introduced yet — single-machine dev today; revisit if a second dev machine
  or CI needs enforced parity.
- State management: **Riverpod** (`flutter_riverpod`), decided phase 1 —
  stream-friendly for the amp's periodic status broadcast, context-free so
  Android/iOS UI variants can share domain logic, and easiest to unit-test
  the networking layer in isolation (`ProviderContainer`/provider overrides,
  no widget tree required).
- Testing: `flutter_test` (bundled) only — no mocking library. The
  networking layer exposes one small `UdpTransport` interface, so a
  hand-written `FakeUdpTransport` (`test/networking/fake_udp_transport.dart`)
  is clearer than pulling in a mocking package for a single fake.
- Project structure: `lib/networking/` (protocol encode/decode + transport,
  pure Dart, zero Flutter imports — verified via
  `grep -rn "package:flutter" lib/networking/`), `lib/domain/` (Riverpod
  providers wrapping the networking layer), `lib/config/` (cross-cutting
  app config, e.g. the UI variant switch), `lib/ui/` (widgets; currently
  just the Phase 1 debug scaffold).
- Repo/branching: `devialet-expert-remote-app`, feature work on branches like
  `feature/amp-selection`.