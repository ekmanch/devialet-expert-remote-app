# TODO

Running list of deferred work for `devialet-expert-remote-app`. Update this
alongside code changes rather than letting it drift — treat it as the source
of truth (not chat history / memory). Cross-checked against the KDE widget
(`devialet-expert-remote-kde`, the most robust implementation) on
2026-09-15; the reasoning behind every closed item lives in `docs/`, not
here.

## Numbering

Work here is tracked as **Tasks**, numbered `major.minor.patch`. The major
number follows CLAUDE.md's port plan (1 scaffold + networking — done; 2
Control-screen UI; 3 architecture + wiring; 4 iOS-specific; 5 polish); the
minor number is one scoped piece of work with its own commit(s); the patch
number is for follow-ups to a task that is otherwise done. Don't merge
tasks into one "domain layer" item. Any "Phase N.N.N" citation in this repo
(CLAUDE.md's PR review checklist, `docs/`) is the **KDE widget's** own
history, not a task here.

Ordering rationale (restructured 2026-09-19): the Control screen's UI is
built first, from the mockups, with no protocol behind it (Task 2.0.0);
then the state owner and persistence layer are *designed* (Task 3.0.0)
before a single control is wired, because checklist items 1, 2, 3 and 7
(late broadcasts vs optimistic state, one owner, synchronous writes,
untrustworthy post-boot reports) all bit every earlier implementation that
wired controls first and centralised later. Settings (3.1.0) come before
volume wiring because volume needs the clamp values; power/boot (3.2.0)
comes before volume because the amp drops commands while Off/Booting.

**Form factors (owner decision 2026-09-19):** the app targets **phones and
tablets** on both platforms (the owner's iPad is a first-class device,
alongside the Galaxy S25). The iOS scaffold already builds for iPhone +
iPad (`TARGETED_DEVICE_FAMILY = "1,2"`, all four iPad orientations in
`Info.plist`) and the Android manifest already handles `screenSize` /
`smallestScreenSize` config changes, so nothing *blocks* tablets today —
but the v19 mockups are a single phone-width column with no breakpoints,
and no doc mentions tablets. Form factor is therefore folded into the
tasks below as a cross-cutting concern rather than a late "tablet task":
layout is chosen by **window width class** (compact / medium / expanded,
per Material 3 and iPadOS size classes), never by device type, because a
tablet can present a phone-width window (iPad Split View / Slide Over /
Stage Manager, Android split-screen and resizable windows) and change it
at runtime. The two-pane expanded layout itself is Task 3.8.0, deferred
until Control and Settings exist. Note CLAUDE.md still names only the Galaxy
S25 as a test device; add tablets there when it is next edited.

## Closed by the KDE cross-check (2026-09-15)

Nothing was implemented here; these were open *questions* that now have
answers, and the implementation work reappears as task items below.

- [x] **Power-on "Booting up…" state (was: 10–15 s timeout, red tint).**
      Solved in KDE with different numbers — real boot is 15.0–18.6 s, so
      10–15 s would flash a failure on every normal boot. Spec: 20 s
      timeout, silent fallback to Off, late confirmation still corrects.
      → `docs/protocol.md` "Timing facts"; designed in Task 3.0.0, wired in
      Task 3.2.0.
- [x] **"Not responding" state (grey-out like no-amp-selected).** Solved
      and extended: Off and Booting disable every control except power
      (dimmed 0.4, last-known labels kept); not-connected dims whole
      groups. → `docs/protocol.md` "Multi-amp discovery"; presentation in
      Task 2.0.0, gating in Task 3.2.0.
- [x] **Volume debounce "port carefully, once per input" (gotchas #1/#2).**
      Replaced by an owner-level pending mask + unmasked confirmed channel
      + synchronous optimistic writes. → `docs/known-gotchas.md` #1/#2
      "Superseded design"; Task 3.0.0.
- [x] **−15 dB ceiling at both layers (gotcha #6).** Owner decision
      2026-09-14: ceiling is a setting, default −10.0, required constructor
      parameter. → `docs/known-gotchas.md` #6 "Decision update"; Task 3.1.0
      (value) + Task 1.1.0 (parameter).
- [x] **Forced −40 dB after source switch (gotcha #5).** Kept, made the
      startup-volume setting, and measured: no settling delay needed (6/6).
      → `docs/protocol.md` "Per-input volume memory"; Task 3.1.0 + 3.5.0.
- [x] **"Amp-initiated volume changes not reflected unless we sent one
      first."** Root-caused as amp firmware, not the client.
      → `docs/known-gotchas.md` #8; stop looking for it in the client.
- [x] **mDNS retry bursts "should not be assumed to carry over".**
      Confirmed an `NsdManager` artefact; one continuous browse resolves in
      < 0.6 s. → `docs/protocol.md` "mDNS model-name resolution".
- [x] **Monotonic clock for all timers.** Same conclusion in KDE; the 400 ms
      / 500 ms / 1500 ms / 8 s / 20 s timers all run on one monotonic
      source. → `docs/protocol.md` "Timing facts"; folded into Task 3.0.0.

## Not planned (don't reintroduce)

- **Volume-feedback chime and its settings** (chime toggle, sound-source
  picker). Owner decision 2026-09-14: the phone is not the amp's audio
  source, so a chime on the phone confirms a gesture and says nothing
  about the amp. The transferable lessons survive as CLAUDE.md checklist
  items 25 and 26; no chime feature, toggle or setting goes in the
  settings list.
- **Translucent / opacity appearance settings** unless an actual
  translucent surface exists on mobile (checklist item 24 keeps the maths).
- **"Forget remembered amps" feature** — amps are in-memory only and the
  active one could never be forgotten; the KDE widget dropped it.
- **Live "updated Xs ago" ticker** in the footer — deliberately dropped in
  KDE for a static "Connected / Not responding / Not connected".
- **Sound tab (SAM / Night Mode / Bass / Treble)** — no wire commands exist
  (`docs/protocol.md`, "Known-unimplemented commands"); the v19 mockups
  drop the Control/Sound switcher entirely. Reopen only if the tcpdump
  workstream below finds the bytes.

## Task 1.1.0 — Networking follow-ups (from the 2026-09-15 reconciliation)

Small, wire-level, unit-testable; no domain layer needed. Details in
`docs/protocol.md`, "Code vs. doc reconciliation".

- [ ] **Quantize to the nearest 0.5 dB before `dbConvert`.** Today the
      Dart recursion rounds *up* on non-half-step input (15.2 → the 15.5
      word; 15.0000001 → the 15.5 word), so upward float drift sends
      0.5 dB louder than intended. Round to nearest and recurse on an
      integer step count, as the Rust crate does; keep exact-step output
      byte-identical.
- [ ] **Add the golden vectors as regression tests:** CRC `"123456789"` →
      `0x29B1`; power-on packet at counters (0,0) → `… A0 BD`;
      `dbConvert` 1.0/15.0/40.0 → `3F80`/`4170`/`4220`; status raw 111 →
      −42.0; all seven source byte pairs from the protocol table.
- [ ] **Drop the per-index source names from `source_mapping.dart` /
      `command_payloads.dart` comments and rename `phonoStatusIndex`** —
      names are per-unit (`docs/protocol.md`, "Names are per-unit").
- [ ] **Make the ceiling a required parameter** on `setVolume` /
      `encodeCommandWord` with an explicit "none" value (checklist item
      28). Do this together with Task 3.1.0 so
      `VolumeCodec.defaultSafetyMaxDb`, the UI range and the −15 pinning
      test change **once**; listed here so it isn't forgotten if 3.1.0 is
      split.

## Protocol verification (tcpdump workstream — unnumbered, runs alongside)

- [ ] **Confirm counter-caveat behavior via tcpdump.** Both counters
      advance on every wire send and restart at (0,0) per process in the
      Kotlin app, the Dart layer and the KDE CLI; the amp accepts all of
      them, which is weak evidence it ignores counters but not a capture.
      Capture real traffic and settle whether the amp needs contiguity or
      the duplicate send at all.
- [ ] **Confirm fallback-to-raw-index behavior for unmapped sources.**
      Still unverified on both sides (index 9 vs 14 both showed "Air",
      judged a no-op). Needs a distinct starting source plus a capture.
- [ ] **Fresh tcpdump captures toggling Night Mode, SAM level, bass, and
      treble** from the Devialet phone app, diffed against the baseline
      heartbeat, to check for byte-level changes in the UDP broadcast.
      (SAM on/off already confirmed to produce no change.) Prerequisite for
      any Sound-tab implementation; not attempted in KDE either.
- [ ] **Adaptive retry under Wi-Fi loss.** Not solved anywhere; fixed
      double-send is all that exists. Decide after the capture above says
      whether the duplicate matters.

## Task 2.0.0 — Control screen UI from the v19 mockups (UI only)

Adopt the design mockups for the **Control screen only**:

- Android: `design/mockups/devialet_remote_mockup_Android_v19.html`
- iOS: `design/mockups/devialet_remote_mockup_iOS_v19.html`

Scope: widgets, layout, theming and every *visual state* of the Control
screen, driven by a debug/fake state object — **no protocol wiring, no
state owner, no persistence**. The mockups are "Control only" in the sense
that the Kotlin app's Control/Sound tab switcher is gone (the Sound tab is
not planned, above). Note that both mockups *also* contain a Settings page
(push-navigated from the header gear), a Theme bottom sheet and an About
group; those are **out of scope here** and belong to Task 3.1.0.

Per-variant through `uiVariantProvider` (CLAUDE.md, "Runtime UI variant
switching"); conventions differ, behaviour below does not.

- [ ] **Adaptive layout from the first commit (phones + tablets).** The
      mockups describe the *compact* width class only. Build the Control
      screen against a width-class value (compact / medium / expanded)
      read from the window, not from `Platform`/device type, and give
      every width class a layout: compact = the mockup verbatim;
      landscape on a phone treated as compact-height rather than ignored;
      medium/expanded = an **interim** centred, max-width content column
      so the dial and buttons don't stretch across a tablet. The real
      expanded layout is **two-pane** (owner decision 2026-09-19, see
      Task 3.8.0) and is deliberately *not* built here: it needs its own
      mockup pass, and tablet verification is deferred because loading
      the iPad is a whole process the owner doesn't want early in the
      port. The width-class plumbing must still be in place now so 3.8.0
      is a layout swap, not a refactor.
- [ ] **Window-size changes at runtime** (rotation, iPad Split View /
      Slide Over / Stage Manager resize, Android split-screen) must
      rebuild the layout without losing state: open sheet, in-progress
      dial drag, draft settings survive a width-class change (the Kotlin
      app handled rotation itself via `configChanges`; Flutter has no
      equivalent free pass — `docs/app-overview.md`, "Screen/orientation
      handling").
- [ ] **Header / amp card:** whole row is the tap target; shows
      `model ?? name` with the IP and a static status word; nothing-selected
      header reads "No Amplifier" / "Tap to connect". Device dot states:
      connected / booting (pulsing amber) / off / none (plain outline).
- [ ] **Amp bottom sheet (static):** "None" is always the first row, above
      a divider, italic, plain outline dot; strings verbatim from the
      Android app: "None" / "Don't connect to any amplifier". Rows show
      `model ?? name` with a " · name unresolved" tag when only the UDP
      name is known; selected row has a check. Manual-IP entry view kept
      inside the same sheet.
- [ ] **Volume dial + VOL −/+ buttons + dB readout.** Slider hit target
      larger than the painted track; the readout binds to the live drag
      value. The mockup's dial range is hardcoded −60..−15 and the arc
      geometry is ported from `VolumeDialView.kt`; the *range* must come
      from the floor/ceiling settings once Task 3.1.0 exists — don't bake
      the mockup's numbers in (checklist items 14, 15).
- [ ] **Mute control:** toggle with label Mute/Unmute **and** a glyph that
      follows state; readouts show the word "Muted" instead of a dB value
      when muted.
- [ ] **Power control and Booting presentation:** spinner replaces the
      power glyph, label "Powering on…", pulsing amber status dot, header
      subtext "Booting…", power control genuinely inert while Booting.
- [ ] **Buttons whose label changes** ("Mute"↔"Unmute", "Power
      On"↔"Powering on…") sized to their widest possible content, measured
      on the Galaxy S25, so nothing shifts on toggle (checklist item 16).
- [ ] **Disabled presentation:** Off / Booting / not-responding: every
      non-power control dimmed to **0.4** opacity, disabled, **keeping
      last-known text** ("−25.0", "Unmute", source name). Not-connected
      dims whole groups (volume, actions, source) per group, dB shows "—".
- [ ] **Source row:** closed row shows an icon chip following the active
      source's glyph, eyebrow label, name (elide at 16 chars — "Chromecast
      Audio" is the stress case), caret; placeholder "No source". Open: a
      floating list / bottom sheet over the row (nothing below moves),
      active row highlighted with a check; empty state when there are no
      sources.
- [ ] **Footer status:** static "Connected" / "Not responding" / "Not
      connected".
- [ ] **Theme tokens** (copper/graphite palette, dark + light variants)
      lifted from the mockup CSS into one place so Task 3.1.0's Theme
      setting and Task 5.0.0's icon can reuse them. Fonts in the mockups
      are Google-hosted (Space Grotesk / JetBrains Mono / Inter) — bundle
      what ships or pick platform fonts; an asset outside the bundle
      renders as nothing (checklist item 18).
- [ ] **Debug state driver:** a debug-only control (not a hidden gesture)
      that cycles the fake state through connected / off / booting /
      not-responding / not-connected / muted so every state above can be
      eyeballed on the Galaxy S25 without an amp.
- [ ] **Hands-on check on the Galaxy S25** in both UI variants, report
      recorded here (checklist item 23), before the task is called done.
      The interim expanded column is checked on an Android tablet
      emulator or a resizable desktop window only — **no iPad load in
      this task**. Measured row heights and button widths are per width
      class (checklist items 14, 16).

## Task 3.0.0 — Software architecture: state owner + persistence layer

**Design first, then implement the core.** A written design (in
`docs/app-overview.md` or a new `docs/architecture.md`) precedes any
control wiring, because checklist items **1, 2, 3 and 7** are all owner-
level concerns: a late broadcast can only be masked correctly by the one
place that knows *when* it sent; two surfaces guessing independently will
diverge; rapid repeat only works if the optimistic write is synchronous in
the owner; and a post-boot report is only trustworthy after the owner has
set a value and waited. Wiring buttons before this exists reintroduces
gotchas #1/#2 one input at a time.

### 3.0.0-a — State owner (Riverpod)

- [ ] One Riverpod-owned live amp state, injected into every surface as a
      *required* dependency; views never keep private copies of
      volume/mute/ip/power (checklist items 2, 5).
- [ ] **Confirmed-vs-optimistic split:** the owner exposes both a
      *displayed* value (optimistic, masked) and a separate unmasked
      **confirmed** value taken from the raw status byte; exact equality,
      no epsilon (`docs/protocol.md`, status notes). Feedback (Task 3.7.0)
      derives from confirmed state, never from the gesture (checklist
      item 25).
- [ ] Optimistic writes are **synchronous, before the async send**, so each
      step accumulates on the stored value (5 taps 10 ms apart = 5 steps);
      rollback on send failure (checklist item 3; `docs/protocol.md`
      reconciliation #6).
- [ ] All timers on one monotonic clock source; staleness `online =
      last_seen < 8 s` on a 1 s tick.
- [ ] Status broadcasts are **triggers, not truth**: re-read state after a
      change rather than trusting a single field; never assume fields of
      one update arrive atomically (checklist items 12, 13).
- [ ] Only the broadcast whose sender IP matches the selected amp updates
      live control state; every broadcast feeds the discovery map (Task
      3.6.0 owns the map's semantics).
- [ ] **No "one screen at a time" assumption.** On expanded widths
      Control and Settings (or Control and the amp/source lists) can be
      visible and interactive *simultaneously*, and two windows of the
      app can exist on iPadOS / Android multi-window. So: every
      cross-view value (volume, mute, power, source, selected amp, the
      settings draft) has exactly one owner and no view-local copy
      (checklist item 2); sheet/list open-closed state and the "reset
      sheets when the screen is left / power leaves On" rule (Task 3.5.0)
      are owner-driven and expressed in terms of *what is visible*, not
      of navigation routes; a settings Apply must reflect on a Control
      pane that never left the screen (checklist item 11's re-trigger).
- [ ] **Width class is injected like the UI variant:** one
      `windowSizeClassProvider` (or equivalent) derived from the window,
      overridable in tests and by a debug define, so layouts and any
      per-width constants read it rather than `MediaQuery` ad hoc, and
      so a phone-width window on a tablet gets the phone layout by
      construction (checklist item 28).

### 3.0.0-b — Pending-command mask + confirmed channel

- [ ] 400 ms pending mask in the state owner (not in widgets): after a
      local command the local value is authoritative until a broadcast
      exactly matches it (confirmed) or 400 ms elapse (fall back to the
      amp's value). A newer command replaces the value and re-arms the
      deadline. Covers volume, mute, power, source in one place (checklist
      item 1).
- [ ] Unit tests with `FakeUdpTransport` reproducing gotchas #1/#2 (late
      pre-change broadcast) and proving the mask absorbs them; prove the
      assertion catches the bug by reintroducing it (checklist item 20).

### 3.0.0-c — Power / boot state machine

- [ ] States Off / Booting / On. Booting starts on a local power-on, ends on
      the amp's confirmation or a **20 s** timeout that silently falls
      back to Off; a late confirmation still corrects to On; repeated
      power-on taps don't extend the deadline. Power-off stays immediate.
- [ ] A "commands allowed" predicate derived from the machine (On and
      connected only), exposed so Task 3.2.0 can gate **every** entry point
      through the same function (checklist items 6, 28).
- [ ] **Startup volume on a self-initiated power-on:** 500 ms after the
      confirming broadcast, send the configured startup volume
      (gotcha #9). Not on an externally triggered power-on (owner decision;
      that path stays exposed to gotcha #8; checklist item 7).
- [ ] **Post-boot display hold:** hold the shown volume at the target,
      record but don't apply incoming pushes, release on a *confirmed* value
      equal to the target or after 1500 ms. A user change inside the window
      re-targets both the hold and the deferred send.

### 3.0.0-d — Settings persistence layer

- [ ] **Decision (recorded here so it isn't relitigated):** app
      preferences live in **app-local storage via the `shared_preferences`
      plugin** (`SharedPreferences` on Android, `UserDefaults` on iOS) —
      the same footprint the Kotlin app used for `amp_ip` / `amp_name`.
      Explicitly **not** Android `Settings.Panel` and **not** an iOS
      `Settings.bundle`: those are for OS-gatekept configuration
      (permissions, system toggles), not app preferences, and would split
      the settings across two UIs with two persistence paths.
- [ ] One typed settings object with named keys, defaults and validation
      in one place; controls are stateless and emit intents, the owner
      writes back (checklist item 9). Every value is stored on change and
      read back on open (checklist item 8).
- [ ] Self-heal on load: an invalid stored pair or out-of-range value is
      repaired **before anything binds** (the specific rules are Task
      3.1.0's; the hook lives here).
- [ ] Testable against a disposable instance
      (`SharedPreferences.setMockInitialValues`, `ProviderContainer`
      overrides); nothing writes the real store from a test (checklist
      item 19).
- [ ] Verify persistence through a **real app restart** (kill, not
      hot-reload) on the Galaxy S25 (checklist item 21).

## Task 3.1.0 — Settings screen: UI + wiring to the persistence layer

**Mockup status:** the v19 mockups (both variants) already include a
Settings page reached from the header gear: Volume Step Size (0.5 / 1 /
2 dB segmented), Startup / Source-Switch Volume, Volume Floor, Volume
Ceiling (1 dB steppers with hold-to-repeat and tap-to-type), an
Appearance group with a Theme sheet (Follow System / Dark / Light) and an
About group (Version, View on GitHub). So no fresh mockup pass is needed
for the volume settings; the mockup does **not** show the selected-amp /
manual-IP setting, "Restore Defaults", the 1 dB gap refusal, or the
blocked-stepper dimming — decide whether to sketch those in the HTML
first (this repo's mockups-before-code convention) or take them straight
from the KDE widget's settings page.

### UI

- [ ] Settings screen per variant (Material list on Android; grouped
      inset-style on iOS, native back behaviour), from the v19 mockup.
- [ ] **Navigation per width class:** compact = push from the header gear
      as in the mockup, and that is all this task builds. On the interim
      expanded column the same push is used. The two-pane variant
      (Settings beside Control) is Task 3.8.0's; design the draft/Apply
      flow now so it doesn't care whether Control is visible at the same
      time: back behaviour, the dirty-draft "discard changes?" guard and
      Restore Defaults must work identically in both, and a draft must
      survive the layout switching between them mid-edit (rotation of an
      iPad while Settings is open is the eventual test case).
- [ ] Draft → Apply/OK, not written from the click handler; "Restore
      Defaults" lives in the page and feeds normal dirty tracking.
- [ ] Steppers: a tap moves exactly 1 dB; hold-to-repeat with
      acceleration; tap the value for direct numeric entry. The mockup's
      420 ms / 140→45 ms timings are a guess until measured (checklist
      item 14).
- [ ] The blocked stepper (floor/ceiling at the 1 dB gap) dims to 0.4 and
      refuses — no silent no-op, no flash.
- [ ] Settings list for v1: floor, ceiling, startup volume, step size,
      selected amp / manual IP. **Decision needed before adding:** the
      mockup's Theme (system/dark/light) and About (version, GitHub link)
      rows are not in this list; record the decision here either way.
- [ ] A setting that reflects external state (notification permission,
      local-network permission, background refresh) stores no bool: query
      on open, apply on Apply, re-query after every write, derive the
      control from the answer; if it can't be toggled, disable it and say
      why in a visible note (checklist item 26).

### Values and rules (wired to Task 3.0.0-d)

- [ ] Three persisted dB values over −96..0: floor **−45.0**, ceiling
      **−10.0**, startup **−40.0** (the mockup shows floor −50 as sample
      content; the owner decision of 2026-09-14 is −45). Change
      `VolumeCodec.defaultSafetyMaxDb`, the UI range and the −15 pinning
      test **together, once**, reading from the settings object (gotcha
      #6, checklist item 28; the required-parameter part is Task 1.1.0).
- [ ] Ceiling enforced inside the command constructor as a required
      parameter with explicit "none"; floor is UI-only and never reaches
      the wire. `DevialetClient.sourceSwitchVolumeDb` becomes the startup
      setting.
- [ ] Step size setting: 0.5 / 1 / 2 dB, default **1.0**.
- [ ] Floor and ceiling mutually constrained at the point of interaction,
      **1 dB minimum gap**. Self-heal an invalid stored pair on load to
      floor −40 / ceiling −39 before anything binds.
- [ ] "Restore Defaults" writes in constraint-safe order (**widen first**)
      so every intermediate state is valid (checklist item 10).
- [ ] Every control persists and is verified after a real restart
      (checklist items 8, 21).
- [ ] The clamp that a limit change applies *to the amp* is Task 3.3.0's
      (it needs the pending mask and the power/boot re-trigger); this task
      only stores and validates.

## Task 3.2.0 — Power / boot wiring (depends on 3.0.0-c)

- [ ] Power button → owner → `powerOn` / `powerOff`; Booting presentation
      from Task 2.0.0 driven by the machine; Booting is entered only on a
      self-initiated power-on.
- [ ] Every control except power is disabled while Off or Booting (the amp
      drops commands in those states); power is live while Off, disabled
      while Booting. **Enumerate every entry point** (buttons, dial drag,
      mute, source sheet, amp sheet, any hardware-key passthrough) and
      route each through the one predicate (checklist item 6).
- [ ] Startup-volume send and post-boot display hold observed end-to-end
      on the real amp: raw UDP capture next to the app, ≥ 3 boots, report
      recorded here (checklist item 22).

## Task 3.3.0 — Volume wiring: buttons + dial (depends on 3.0.0-b, 3.1.0)

- [ ] One discrete input (tap, hardware key if ever mapped) = exactly one
      step of the configured size; the dial snaps to the same step.
- [ ] Hold-to-repeat: 300 ms initial delay, 100 ms interval (measured, not
      the mockup's 400/100 — checklist item 14).
- [ ] Every step path computes `clamp(base + dir·step)` on the
      already-clamped synchronous value; clamp is idempotent.
- [ ] One fraction value feeds every meter (dial arc, any indicator bar);
      never computed three times.
- [ ] Exception, by design: an actively dragged dial displays its own
      local position, not the round-tripped value; block scroll/wheel-style
      deltas entirely while a drag is in progress.
- [ ] Auto-unmute on a *user* volume change (±, dial) — a client decision;
      the wire does not unmute (`docs/protocol.md`, "Volume and mute are
      independent").
- [ ] **Limit-change clamp:** immediate clamp when floor/ceiling change,
      both directions, scoped to the connected amp, amp stays muted through
      it, one Apply changing both values coalesced into exactly one
      command, nothing sent when already in range; re-run on connection
      landing and on power reaching On (checklist item 11).
- [ ] Verified against gotchas #1/#2 by hand on the Galaxy S25 (release
      the button / the dial mid-broadcast) with a raw capture next to the
      app; report recorded (checklist items 22, 23).

## Task 3.4.0 — Mute wiring (independent; do early if convenient)

- [ ] Mute is its own opcode, independent of volume; the owner exposes it
      through the same pending mask as everything else.
- [ ] Corrections sent while muted (limit clamps, startup volume) leave the
      amp muted; only Task 3.3.0's auto-unmute on a *user* volume change
      unmutes.
- [ ] Numeric readouts derive "Muted" from confirmed+masked state, not from
      the button's own toggle (checklist item 9).

## Task 3.5.0 — Source selection wiring

- [ ] Names come from the live broadcast only; always 30 slots, `selected`
      derived per slot, filtered to enabled for display; bounds-check the
      chosen index where the model lives. Never hardcode a per-unit name
      for an index (`docs/protocol.md`, "Names are per-unit").
- [ ] **Every switch sends the forced startup volume** (Task 3.1.0's value,
      source×2 then volume×2, zero delay) — so **never bind a casual
      gesture (scroll, swipe) to cycling sources**.
- [ ] Amp sheet and source sheet mutually exclusive by code; both reset to
      closed when the screen is left or when power leaves On.
- [ ] Diff keys include selection state, not just names (gotcha #4).

## Task 3.6.0 — Amp discovery / selection list wiring

- [ ] Discovery map keyed by sender IP, updated by every broadcast, never
      evicted; silent amps flip to offline after 8 s; the sheet's list
      refreshes live while open.
- [ ] Persist selection with **two distinct states**: "chosen X" and
      "chosen nothing (None)", plus a "user has chosen" flag, so restart
      never resurrects a default the user opted out of (checklist item 4).
- [ ] Auto-select-if-alone: nothing selected, never chosen, exactly one amp
      known → that amp; 0 or 2+ → not-connected, don't guess.
- [ ] Manual-IP fallback: a never-heard IP is a valid selection; no
      reconciliation step, staleness governs connectedness.
- [ ] Not-connected state: name `""`, offline, sources `[]`, power Off, and
      **no volume reading** — check "is there an amp" before any clamp so a
      zero default can't display as "−15.0 dB" (checklist item 5).
- [ ] mDNS model name: `_spotify-connect._tcp.local.`, trusted only for an
      IP already heard over UDP, resolved once, carried across
      re-ingestion; `parseModelName` per `docs/protocol.md` with its three
      test cases. Platform-native browse per OS (no `NsdManager` restart
      bursts); iOS needs `NSBonjourServices` + local-network permission
      (see Task 4.0.0).

## Task 3.7.0 — Transient feedback (lower priority; can trail the above)

- [ ] A local-interaction cue (fires only from your own gesture) with
      reset-and-replace semantics: each new value cancels the pending
      dismiss, snaps content, restarts a fixed **1800 ms** timeout; no
      queueing. Icon tiers: muted or ≤0 % → mute, ≤25 % low, ≤75 % medium,
      else high. Content derives from confirmed state (checklist item 25).
- [ ] Any passive mirror (home-screen widget, notification, watch
      complication — if ever built) reflects shared state including
      remote-originated changes; the transient cue does not.
- [ ] Don't reuse the OS's own volume OSD look; users mistake it for the
      device's volume. No mockup exists for this cue yet — sketch it in the
      v19 HTML before building.

## Task 3.8.0 — Expanded-width two-pane layout (tablets; after 3.1.0)

**Owner decision 2026-09-19:** expanded widths get a **two-pane layout**
(it will look nicer on a tablet than a centred phone column). Deferred to
here, after the Control and Settings screens exist and are wired, because
the owner's only tablet is an iPad and loading the app onto it is a whole
process that shouldn't gate early tasks. Everything in this task is
previewed on an **Android tablet emulator or a resizable desktop window**
via both UI variants; the real-iPad check is Task 4.4.0.

- [ ] **Tablet mockup pass** in the v19 HTML (both variants) before any
      code: which pane pairs are shown at expanded width (Control +
      Settings; Control + amp/source lists), what medium width does
      (probably still single-pane, wider column), pane proportions, where
      the header/amp card lives, and how sheets become popovers / form
      sheets / side panels per platform (mockups-before-code; checklist
      items 14, 15 — measure the mockup, don't trust its declared numbers).
- [ ] Build the two-pane layout on Task 2.0.0's width-class plumbing,
      replacing the interim centred column; compact stays the mockup
      layout untouched.
- [ ] Settings in the side pane: same draft/Apply component as Task
      3.1.0, no second copy of the draft; Apply is reflected on the
      Control pane that never left the screen (Task 3.0.0-a's "no one
      screen at a time" rule; checklist items 2, 11).
- [ ] Width-class transitions while connected (rotate, resize) keep the
      open sheet / drag / draft (Task 2.0.0's runtime-resize item),
      re-checked with two panes.
- [ ] Hands-on check on the emulator / desktop window recorded here; the
      iPad soak stays in Task 4.4.0 / 5.0.0.

## Task 4.0.0 onward — iOS-specific (after 2.x/3.x are proven on Android)

- [ ] **4.0.0** Local-network permission flow
      (`NSLocalNetworkUsageDescription`, `NSBonjourServices`), incl.
      "denied" and "not yet asked" states, surfaced as an external-state
      setting per Task 3.1.0 (checklist items 17, 26).
- [ ] **4.1.0** Backgrounding: expect status loss within seconds; design
      the resume path (re-bind, staleness re-evaluation, pending mask and
      boot machine reset) rather than assuming parity (checklist item 30).
- [ ] **4.2.0** ATS / `NSAllowsLocalNetworking` for plaintext UDP.
- [ ] **4.3.0** iOS UI pass on a physical device: everything Task 2.0.0
      previewed through the `ios` UI variant on the Galaxy S25, re-checked
      on real iOS (fonts, safe areas, back behaviour, sheet dismissal).
- [ ] **4.4.0** iPad pass on the owner's iPad — the **first** time the app
      is loaded onto it, by design (Task 3.8.0): every width class via
      Split View, Slide Over and Stage Manager resizing while connected
      (state survives, sockets don't); all four orientations already
      declared in `Info.plist`; decide and record whether
      `UIRequiresFullScreen` stays off (it must, for multitasking);
      sheets become popovers/form sheets per iPadOS convention;
      local-network permission (4.0.0) and backgrounding (4.1.0)
      re-checked on iPadOS, which suspends a Slide Over window on its own
      schedule. App Store iPad screenshots are part of the deliverable.

## Task 5.0.0 — Polish

- [ ] **Custom app icon.** Copper/graphite visual language, replacing stock
      Flutter/Android/iOS default icons. The KDE widget shipped a copper
      glow-dot panel icon and a brand tile picker icon in that language
      (`icons/hicolor/scalable/apps/`, `plasmoid/contents/icons/` in that
      repo) — reuse the assets/tokens if the brand should match. Concept
      directions explored previously: Dial Arc, Signal Dot, Waveform Bars,
      Faceplate, Concentric Rings.
- [ ] Human soak on the Galaxy S25 **and the iPad** with the gesture-only
      checks listed and the report recorded (checklist item 23), before
      calling any UI task done. Android tablet coverage is emulator-only
      until a physical Android tablet exists; say so in the report.

## Build / tooling (unnumbered)

- [ ] **AGP declarative DSL migration** (only relevant if/when native Android
      build tooling is touched directly). Non-urgent, still supported through
      AGP 9.x.
- [ ] **`targetSdk` bump (34 → 37)** — once bumped to Android 17, raw UDP
      socket usage will require the new `ACCESS_LOCAL_NETWORK` runtime
      permission. Handle both together, not separately; the permission
      flow then mirrors Task 4.0.0's iOS one (checklist item 17).
- [ ] **Large-screen Android readiness:** keep `resizeableActivity`
      unrestricted (no fixed portrait `screenOrientation`), and check the
      manifest against Google Play's large-screen guidelines once Task
      2.0.0's adaptive layout lands; tablet-emulator run configuration
      added next to the two Galaxy S25 ones in Android Studio.

## Docs (unnumbered)

- [ ] Once the tcpdump items above are resolved, update `docs/protocol.md`
      to flip their status from "inferred, not confirmed" to confirmed (or
      correct them if the capture reveals different behavior than assumed).
- [ ] `docs/protocol.md` and `docs/known-gotchas.md` still point into this
      file with the old wording ("Phase 1 follow-ups", "volume-limits
      phase", "state owner / pending-command mask phases"). Retarget those
      pointers to Task 1.1.0 / 3.1.0 / 3.0.0 on the next docs touch.
