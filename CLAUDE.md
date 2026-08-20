# CLAUDE.md

## Project

Flutter remote-control app for the Devialet Expert Pro 140 amplifier, targeting
both Android and iOS. This is a port of an earlier Android-only Kotlin app
(source of truth for protocol and known bugs — see `docs/`).

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

There will be a debug-only mechanism added to force which platform's UI renders,
independent of the actual OS. TBD, decide on exact runtime variable in scaffold phase.
When adding a new screen or widget with platform-specific styling, route the
platform check through this mechanism rather than `Platform.isIOS` /
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
- Package manager / tooling: TBD, decide in scaffold phase
- Repo/branching: `devialet-expert-remote-app`, feature work on branches like
  `feature/amp-selection`.