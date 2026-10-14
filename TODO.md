# TODO

Build order for the Devialet Expert remote. Tasks are numbered `major.minor.patch`: the major number is the port plan (1 scaffold and networking, 2 Control-screen UI, 3 architecture and wiring, 4 iOS, 5 polish), the minor is one scoped piece of work, the patch a follow-up; "Phase N.N.N" anywhere in this repo is the KDE widget's history, not a task here.

Task 2 builds the Control screen on fake state; the state owner and persistence (3.0 to 3.3) are designed before any control is wired, then settings, power, volume, mute, source and discovery are wired in that order. Decisions and measurements live in `docs/` and the commit messages.

## Not planned

- Volume-feedback chime and its settings (the phone is not the amp's audio source)
- Translucent / opacity appearance settings, unless a translucent surface ever exists
- "Forget remembered amps"
- A live "updated Xs ago" ticker
- Sound tab (SAM, Night Mode, Bass, Treble): no wire commands are known

## Task 1.1.x: Networking follow-ups

Small wire-level fixes from the 2026-09-15 reconciliation with the KDE widget (`docs/protocol.md`, "Code vs. doc reconciliation").

- [x] 1.1.0 Quantize to the nearest 0.5 dB before `dbConvert`
- [x] 1.1.1 Golden vectors as regression tests (CRC, power packets, `dbConvert`, status volume, source byte pairs)
- [x] 1.1.2 Drop per-unit source names from comments; rename `phonoStatusIndex`
- [x] 1.1.3 The ceiling is a required parameter on `setVolume` / `encodeCommandWord`, with an explicit "none"
- [x] 1.1.4 Encode the select-source fallback as `bfloat16(index)`; the six pinned byte pairs stay

## Protocol verification

Live runs against the owner's amp from the dev machine; method and results in `docs/protocol-verification-*.md`.

- [x] Counter behavior: the amp ignores both counters; CRC and magic bytes are checked
- [x] Raw-index fallback for unmapped sources (`float32(index)`, truncated by the amp)
- [x] Wi-Fi loss: keep the fixed double send, no adaptive retry
- [x] Accepted limitation: a power-on started by another client shows as Off until the amp reports On
- [ ] Measure broadcast delivery over Wi-Fi on the S25 and the iPad (the desktop's adapter lost about half)
- [ ] Re-run the source probes on a second unit, if one is ever on the LAN

## Task 2.0.x: Control screen UI

The Control screen built from the mockups, now in the alternate layout (power on the amp card, a round −/mute/+ row, the dial filling the spare height). Current mockups: `design/mockups/Devialet Remote Mockup — Android (alternate) v1.html` and `design/mockups/Devialet Remote Mockup — iOS (alternate) v1.html`.

- [x] 2.0.0 Adaptive layout by window width class, with an interim centred column on medium and expanded widths
- [x] 2.0.1 Window-size changes keep the open sheet, the dial drag and typed input
- [x] 2.0.2 Header / amp card with the device dot states
- [x] 2.0.3 Amp sheet with "None" first and the inline manual-IP view
- [x] 2.0.4 Volume dial, VOL −/+ and dB readout; the range comes from state, not the mockup
- [x] 2.0.5 Mute toggle and the "Muted" readout
- [x] 2.0.6 Power control and the Booting presentation
- [x] 2.0.7 Buttons whose label changes are sized to their widest label (gone with the alternate layout: mute and power are icon-only)
- [x] 2.0.8 Disabled presentation for Off, Booting and no amp; the card's power circle dims to 0.35 and absorbs taps
- [x] 2.0.9 Source row and source sheet with an empty state
- [x] 2.0.10 Footer status (removed by the v36 mockups; the card's dot alone shows the link state)
- [x] 2.0.11 Theme tokens and bundled fonts
- [x] 2.0.12 Debug state driver (removed in 2.0.20)
- [ ] 2.0.13 Hands-on check on the S25 in both UI variants and both themes, plus a tablet emulator; record measured row heights and label widths (Android variant soaked on the alternate layout 2026-09-26)
- [x] 2.0.14 Gold foil sheen on the light theme's wordmark
- [x] 2.0.15 v19 → v36 mockup pass for Control, Settings and the sheets
- [x] 2.0.16 Painted source and theme glyphs, painted tick, larger device dot, accented section headings
- [x] 2.0.18 Painted "Enter IP Manually" glyph with optical sizing; one shared leading slot in the amp rows
- [x] 2.0.19 v39 mockup update: smaller source name, back chevron in the manual-entry view, "AIR", gold dB readout
- [x] 2.0.20 Debug state driver and the Task 1 network screen removed
- [x] 2.0.21 The Control column fits the S25 without scrolling (synced to the mockups as v40)
- [ ] 2.0.22 Small phones: the dial already grows into spare height (filled layout); shrinking it below 220 dp on short screens is not done

## Task 3.0.x: State owner

One Riverpod owner of the live amp state, designed in `docs/architecture.md` before any control was wired.

- [x] 3.0.0 One owner, injected as a required dependency; views keep no copies
- [x] 3.0.1 Displayed (optimistic) and confirmed (raw) values kept apart
- [x] 3.0.2 Optimistic writes are synchronous, before the send, with a rollback
- [x] 3.0.3 One monotonic clock; an amp is online while last seen < 8 s
- [x] 3.0.4 Broadcasts are triggers: every ingest replaces the whole status
- [x] 3.0.5 Only the selected amp's broadcasts update live state; every broadcast feeds discovery
- [ ] 3.0.6 No "one screen at a time" assumption (sheets done in 3.8.2; panes remain for 3.11.x)
- [ ] 3.0.7 Width class injected through a provider, overridable in tests and by a define
- [x] 3.0.8 A silent amp keeps its persisted selection and reconnects without a tap
- [x] 3.0.9 `ControlViewState.volumeDb` is nullable; no floor sentinel

## Task 3.1.x: Pending-command mask

A 400 ms mask in the owner absorbs late pre-change broadcasts for volume, mute, power and source alike.

- [x] 3.1.0 400 ms pending mask, released by an exact confirmation or the deadline
- [x] 3.1.1 Tests reproducing gotchas #1/#2 with `FakeUdpTransport`, with a counter-test

## Task 3.2.x: Power and boot state machine

Off / Booting / On with a 20 s boot timeout, and the startup volume sent after the amp confirms On.

- [x] 3.2.0 Off / Booting / On; 20 s timeout falls back to Off silently; power is sent for real
- [x] 3.2.1 One "commands allowed" predicate for every entry point
- [x] 3.2.2 Startup volume sent 500 ms after the confirming broadcast
- [x] 3.2.3 Post-boot display hold at the target, released on confirmation or after 1500 ms
- [x] 3.2.5 Power-ons started elsewhere get the same hold and startup volume

## Task 3.3.x: Settings persistence

Settings in `shared_preferences` behind one typed object, healed on load before anything binds.

- [x] 3.3.0 `shared_preferences` (not `Settings.Panel` or a `Settings.bundle`)
- [x] 3.3.1 One typed `AppSettings` with defaults and validation; controls emit intents
- [x] 3.3.2 Self-heal invalid stored values in `main()` before `runApp`
- [x] 3.3.3 Tests use an in-memory store; nothing writes the real one
- [ ] 3.3.4 Selection persistence through a real app restart on the S25 (chosen amp, "None", fresh install)

## Task 3.4.x: Settings screen

The mockup's Settings page wired to the persistence layer; settings take effect immediately, following the platform convention.

- [x] 3.4.0 Settings screen per variant, pushed from the header gear
- [x] 3.4.1 Push navigation on every width class for now; the side pane is 3.11.x
- [x] 3.4.2 No draft / Apply: settings are effective immediately (owner decision)
- [x] 3.4.3 Steppers: 1 dB per tap, hold-to-repeat with acceleration, tap to type (timings not yet measured)
- [x] 3.4.4 A blocked stepper button dims and refuses
- [x] 3.4.5 Floor, ceiling, startup volume, step size, theme and About; amp selection stays on the Control screen
- [ ] 3.4.6 Settings that reflect external state (permissions) query instead of storing, and say why when disabled
- [x] 3.4.7 Floor −50, ceiling −10, startup −40 over −96..0
- [x] 3.4.8 The ceiling is enforced in the command constructor; the floor never reaches the wire
- [x] 3.4.9 Step size 0.5 / 1 / 2 dB, default 1
- [x] 3.4.10 Floor and ceiling at least 1 dB apart, enforced at the control
- [ ] 3.4.11 "Restore Defaults" row (deferred; the widen-first logic exists and is tested)
- [x] 3.4.12 Every setting persists across a restart; store errors are shown
- [x] 3.4.13 The limit clamp on the amp is 3.6.6's

## Task 3.5.x: Power wiring

The power button driven by the boot machine, with every other control gated while the amp is Off or Booting.

- [x] 3.5.0 Power button and the Booting presentation driven by the machine
- [x] 3.5.1 Every entry point except power gated while Off or Booting
- [x] 3.5.2 Startup volume and post-boot hold verified on the real amp over six boots

## Task 3.6.x: Volume wiring

VOL −/+ and the dial send for real; the dial sends on release, as in the KDE widget.

- [x] 3.6.0 One tap is one step of the configured size; the dial snaps to the same step
- [x] 3.6.1 Hold-to-repeat at 300 ms / 100 ms
- [x] 3.6.2 One clamp for every step path
- [x] 3.6.3 One fraction function feeds every meter
- [x] 3.6.4 The dragged dial shows its own position; a drag ends uncommitted if the group goes inert
- [x] 3.6.4b A user change inside the post-boot hold counts as the hold's send
- [x] 3.6.5 Auto-unmute on a user volume change
- [x] 3.6.6 Floor / ceiling changes clamp the amp at once, one command, re-run on connect and power-on
- [x] 3.6.7 Gotchas #1/#2 verified on the real amp with a raw capture (the owner's hands-on feel is still to record)
- [ ] 3.6.8 Paced sends during a dial drag (deferred; revisit if live tracking is missed)

## Task 3.7.x: Mute wiring

Mute is its own command through the same pending mask, sent for real alongside 3.6.5.

- [x] 3.7.0 Mute sent for real through the pending mask
- [x] 3.7.1 Corrections (limit clamp, startup volume) leave the amp muted
- [x] 3.7.2 "Muted" derives from owner state, not the button

## Task 3.8.x: Source selection wiring

Source selection sent for real, each switch followed by the startup volume, with sheet visibility owned by the state owner.

- [x] 3.8.0 Source names from the live broadcast only; switches sent through the pending mask
- [x] 3.8.1 Every switch sends the startup volume; no casual gesture cycles sources
- [x] 3.8.2 One owner-driven sheet slot; the source sheet closes when power leaves On
- [x] 3.8.3 The view's equality includes the active source
- [x] 3.8.4 Verified on the real amp across every enabled slot
- [ ] 3.8.5 A failed user volume send inside the boot hold restores the previous value instead of dropping the hold
- [ ] 3.8.6 Owner hands-on: sheet dismissal gestures on the S25 in both variants
- [x] 3.8.7 Mute on a network input with music playing (AIR, Roon Ready)

## Task 3.9.x: Amp discovery and selection

Every amp ever heard stays listed, silent ones as "Not responding", with the model name resolved over mDNS.

- [x] 3.9.0 Live discovery list with offline rows and the waiting phase
- [x] 3.9.1 Selection persisted with a separate "user has chosen" flag
- [x] 3.9.2 Auto-select only when exactly one amp is known and nothing was chosen
- [x] 3.9.3 A typed IP is a valid selection, tagged MANUAL until first heard
- [x] 3.9.4 Not connected shows no volume reading
- [x] 3.9.5 mDNS model name: `multicast_dns` on Android, Bonjour on iOS
- [ ] 3.9.6 Discovery verified on the real amp (scripted half done; the owner's Wi-Fi hand-runs remain)
- [ ] 3.9.7 Owner hands-on: offline rows, the waiting ring and the manual-IP flow on the S25 in both variants

## Task 3.10.x: Transient feedback

A short volume cue after the user's own gestures; lower priority, can trail the rest.

- [ ] 3.10.0 Reset-and-replace cue with a 1800 ms timeout, content from confirmed state
- [ ] 3.10.1 Any passive mirror (widget, notification) reflects remote changes too; the cue does not
- [ ] 3.10.2 Mockup the cue first; it must not look like the OS volume OSD

## Task 3.11.x: Two-pane layout for tablets

Expanded widths get a two-pane layout, previewed on a tablet emulator or resizable window; the real iPad check is 4.4.0.

- [ ] 3.11.0 Tablet mockup pass, both variants
- [ ] 3.11.1 Two-pane layout replacing the interim centred column
- [ ] 3.11.2 Settings in the side pane, reflected on a Control pane that never left the screen
- [ ] 3.11.3 Width-class transitions keep the open sheet and the drag with two panes
- [ ] 3.11.4 Hands-on check on the emulator or a desktop window

## Task 4.0.x: iOS

iOS-specific work, after Tasks 2 and 3 are proven on Android.

- [ ] 4.0.0 Local-network permission flow, and the Bonjour source verified on the iPad
- [ ] 4.1.0 Backgrounding and resume (sockets, staleness, pending mask, boot machine, the mDNS session)
- [ ] 4.2.0 ATS / `NSAllowsLocalNetworking` for plaintext UDP
- [ ] 4.3.0 iOS UI pass on a physical device
- [ ] 4.4.0 iPad pass: every width class via Split View, Slide Over and Stage Manager; App Store iPad screenshots

## Task 5.0.x: Polish

- [ ] 5.0.0 Custom app icon in the copper/graphite language
- [ ] 5.0.1 Human soak on the S25 and the iPad, report recorded

## Later

- [ ] AGP declarative DSL migration, if the native Android build is ever touched
- [ ] `targetSdk` 34 → 37 together with the `ACCESS_LOCAL_NETWORK` permission
- [ ] Large-screen Android readiness: manifest against Google Play's guidelines, a tablet-emulator run config
- [ ] Retarget the old "state owner / pending-command mask phases" pointers in `docs/protocol.md` and `docs/known-gotchas.md` to Tasks 3.0.x and 3.1.x
