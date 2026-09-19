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

A third implementation exists: the KDE Plasma widget
https://github.com/ekmanch/devialet-expert-remote-kde (Rust + QML). It is
by far the most robust and polished version of this app, battle-tested in
daily use, and the source of every ★-marked fact in `docs/protocol.md`,
gotchas #8/#9 in `docs/known-gotchas.md`, and the PR review checklist
below. When the Kotlin app and the KDE widget disagree on behaviour, the
widget wins. Its knowledge transfer was folded into this repo's docs on
2026-09-15; there is no separate set of notes to consult.

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
- Every PR that touches state, networking, settings or timing goes through
  the "PR review checklist" below before it is considered done.

## PR review checklist (settled — do not relitigate)

Thirty root causes that recurred across the Kotlin app, the KDE widget and
this port, regardless of platform. Distilled from the KDE widget's bug
history (its `TODO.md` phase numbers are kept as provenance — "Phase 8.0.1"
is that repo's history, not this one's). Root cause first, mechanism
omitted, then the lesson. Tick each item that applies against the diff;
an item you can't tick with a concrete reason is a finding, not a pass.
Add to this list when a new root cause bites; never remove one because it
"can't happen in Flutter" — most of these were once thought to be
platform-specific.

**State and device truth**

- [ ] **1. Late device broadcast vs optimistic local state** (Kotlin
      gotchas #1/#2, KDE Phase 3/5). The device's periodic report is authored
      before your command and can land after it; a dropped command is never
      confirmed. Lesson: an ignore window keyed off *when you sent*, not "is
      the user touching"; a real confirmation channel to release it; apply
      it once in the state owner so every input method is covered.
- [ ] **2. Two surfaces guessing independently diverge** (Phase 5). Lesson:
      exactly one owner of cross-view state, injected, required (a defaulted
      injection fails silently at runtime; a required one fails loudly at
      construction).
- [ ] **3. Non-synchronous optimistic writes break rapid repeat**
      (Phase 5.0.2). The accumulation base came back from an async round
      trip. Lesson: write locally in the same tick, then send; keep a
      rollback.
- [ ] **4. "Never chosen" and "chose nothing" collapsed into one sentinel**
      (Phase 4.1/4.2). Lesson: a separate "user has chosen" flag, persisted.
- [ ] **5. A zero default masquerading as a reading** (Phase 4.1). Lesson:
      check for device presence before clamping/formatting; a clamp turns a
      missing value into a convincing lie.
- [ ] **6. A control that can't work must be disabled, not allowed to fail**
      (Phase 8.0.1); and **the gate must cover every input path** (mute and
      source were still live after volume was fixed). Lesson: enumerate all
      entry points when adding a precondition; dim, don't blank.
- [ ] **7. The device's own report can be wrong** (gotcha #8) and **the
      earliest "ready" moment is the worst time to send** (gotcha #9).
      Lesson: set a value if you need a trustworthy one; wait for
      confirmation "and then some"; measure the spread, don't sit in the
      middle of it.

**Settings and persistence**

- [ ] **8. Every settings control must persist, not just apply**
      (Phases 4.4.1, 10.1.1). Lesson: verify the stored value survives a
      restart and is read from the right key; a self-consistent wrong result
      from a dead key looks exactly like a bug.
- [ ] **9. A control that mutates its own state severs its binding**
      (Phase 10.1.2, latent since 9.1.0). Lesson: stateless controls that
      emit intents; the owner writes the value back.
- [ ] **10. Reactive validation vs multi-field writes** (Phase 8.3.0).
      Lesson: order writes so every intermediate state is valid (widen
      first) or batch them.
- [ ] **11. Coalesce a multi-field Apply into one action; and a deferred
      check can beat late async data** (Phase 8.4.0). Lesson: defer to the
      end of the tick and no-op when already correct; re-trigger the check
      on every input that can complete late (connection landing, power
      reaching On), not just on the setting that changed.
- [ ] **12. Fields of one logical update do not arrive atomically or in
      your order** (Phase 8.0.1/8.4.0). Lesson: never key a handler on one
      field and read a sibling in the same callback without deferring or
      re-checking.
- [ ] **13. Push payload ≠ truth** (Phase 3/7.2.0). Lesson: treat a
      notification as a trigger and re-read; structured values in
      particular.

**Constants, geometry, assets**

- [ ] **14. Measure, don't copy constants** (15 s→20 s boot timeout,
      "~1 s"→1800 ms toast, 400/100→300/100 repeat, guessed→measured row
      heights, "+200 ms is the middle of the spread"). Lesson: every
      timing/geometry constant from a mockup, another platform or a single
      happy sample is a guess until measured on the real device.
- [ ] **15. A mockup's declared numbers may not describe its own rendering**
      (Phase 4.5.3: fonts failed to load from `file://`). Lesson: port the
      measured result when it disagrees with the declared value.
- [ ] **16. One element positioned from another's current content jitters**
      (Phase 4.5.3 three times, 12.0.0). Lesson: fixed-height rows, each
      child positioned from its own intrinsic size, buttons sized to
      worst-case content ("Mute"/"Unmute", "Power On"/"Powering on…"); when
      the same symptom recurs, audit every element of that kind in one pass
      instead of patching the visible one.
- [ ] **17. Missing dependency looks like a logic regression** (Phase 4.5.0,
      13.0.0: every command failing uniformly). Mobile analogue: a failed
      platform channel, missing permission (iOS local network) or absent
      asset. Lesson: when everything reverts identically, check the shared
      dependency first.
- [ ] **18. Assets outside the shipped bundle render as nothing, silently**
      (fonts, OSD icons; `currentColor` SVGs rendering black). Lesson: the
      asset manifest (`pubspec.yaml` assets, platform icon sets) is part of
      the feature; tint through the framework, not the file.

**Verification discipline**

- [ ] **19. Test scaffolding can pollute real state** (synthetic amp
      persisted in the never-pruned list; a spike wrote the real popup's
      size keys). Lesson: fakes against disposable instances
      (`ProviderContainer` overrides, `FakeUdpTransport`); snapshot/restore
      anything shared (`shared_preferences`).
- [ ] **20. A stability check is not a correctness check** (7.6.0/7.7.0).
      Lesson: assert actual == expected per state and prove the assertion
      catches the bug by reintroducing it.
- [ ] **21. Verify absence after a restart; a cached process hides external
      writes** (7.2.0, 8.3.0). Lesson: test persistence through a real app
      restart (kill, not hot-reload), not against the running process.
- [ ] **22. A passing check with an unexplained reason has not passed**
      (7.2.0, 8.2.0, 7.11.0 screensaver misdiagnosis). Lesson: cross-check
      against the raw source of truth (a raw UDP capture next to the app);
      take a control measurement of something the change cannot affect.
- [ ] **23. Scripted verification is not a substitute for hands-on use**
      (7.8.0, 8.0.1). Lesson: list the gesture-only checks for a human soak
      on the Galaxy S25 and record the report.
- [ ] **24. Layered translucency multiplies; clamped formulas plateau**
      (9.1.1). Lesson: solve backwards from the effective result; avoid
      `min(x,1)` over a live range. (Only bites if a translucent surface
      exists; keep the lesson.)
- [ ] **25. Feedback must describe the real thing, not the gesture**, and
      **latency makes feedback non-atomic** (10.0.0, chime spike). Lesson:
      derive feedback (haptics, tones, toasts) from confirmed state and
      bound the error explicitly.
- [ ] **26. Never silently fall back to a different mode; degrade at the
      point of use and keep the user's choice** (10.1.3). Lesson: a broken
      setting must look broken, not work by accident.
- [ ] **27. Live hardware tests need a stated safety envelope** (chime
      spike: −50..−35 dB only until the gain math was hand-checked) and
      **fake fixtures must not target real hardware** (fictional IPs).
      Lesson: write the envelope down before the first send.
- [ ] **28. Structural guarantees beat per-caller discipline, and state
      their exact boundary** (8.1.0: clamp inside the constructor; a manual
      CLI still can't re-derive the limit, so the flag is required). Lesson:
      put safety in the one function everything passes through and document
      what it cannot cover.
- [ ] **29. Check a brief against the code's own conventions before
      implementing it literally** (8.3.0's inverted floor/ceiling; 9.1.2's
      cited constraint that wasn't in the doc; 7.14.0's "required by bug X"
      that was about RTL). Lesson: go to the working implementation, not the
      secondhand claim.
- [ ] **30. Unattended long runs get interrupted by the environment**
      (screensaver; on mobile: screen lock, Doze, background socket
      suspension). Lesson: inhibit up front; don't diagnose afterwards.

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