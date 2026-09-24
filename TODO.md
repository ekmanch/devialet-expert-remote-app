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
wired controls first and centralised later. Settings (3.4.x) come before
volume wiring because volume needs the clamp values; power/boot (3.5.x)
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
at runtime. **Orientation (owner decision 2026-09-19):** phones are
locked to portrait (`lib/config/orientation_policy.dart`, decided by the
display's shortest side < 600 dp, applied once in `main.dart`); tablets
keep every orientation because 3.11.x's two-pane layout is a landscape
layout. The compact-*height* handling below therefore only matters for
tablets in split screen. The two-pane expanded layout itself is Task 3.11.x, deferred
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
      Task 3.5.x.
- [x] **"Not responding" state (grey-out like no-amp-selected).** Solved
      and extended: Off and Booting disable every control except power
      (dimmed 0.4, last-known labels kept); not-connected dims whole
      groups. → `docs/protocol.md` "Multi-amp discovery"; presentation in
      Task 2.0.0, gating in Task 3.5.x.
- [x] **Volume debounce "port carefully, once per input" (gotchas #1/#2).**
      Replaced by an owner-level pending mask + unmasked confirmed channel
      + synchronous optimistic writes. → `docs/known-gotchas.md` #1/#2
      "Superseded design"; Task 3.0.0.
- [x] **−15 dB ceiling at both layers (gotcha #6).** Owner decision
      2026-09-14: ceiling is a setting, default −10.0, required constructor
      parameter. → `docs/known-gotchas.md` #6 "Decision update"; Task 3.4.x
      (value) + Task 1.1.3 (parameter).
- [x] **Forced −40 dB after source switch (gotcha #5).** Kept, made the
      startup-volume setting, and measured: no settling delay needed (6/6).
      → `docs/protocol.md` "Per-input volume memory"; Task 3.4.x + 3.8.x.
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
  drop the Control/Sound switcher entirely. Reopen only if a capture ever
  finds the bytes (the 2026-09-19 run did not look for them).

## Task 1.1.x — Networking follow-ups (from the 2026-09-15 reconciliation)

Small, wire-level, unit-testable; no domain layer needed. Details in
`docs/protocol.md`, "Code vs. doc reconciliation".

- [x] **1.1.0** — **Quantize to the nearest 0.5 dB before `dbConvert`.** Done
      2026-09-19: quantize once at entry, recurse on an integer step count
      (literal port of the KDE `db_convert`); exact-step output verified
      byte-identical by the golden vectors, and the rounding tests were
      confirmed red against the old recursion before the fix.
- [x] **1.1.1** — **Add the golden vectors as regression tests:** CRC `"123456789"` →
      `0x29B1`; power-on packet at counters (0,0) → `… A0 BD`;
      `dbConvert` 1.0/15.0/40.0 → `3F80`/`4170`/`4220`; status raw 111 →
      −42.0; all seven source byte pairs from the protocol table. Done
      2026-09-19 as literal-byte tests in `test/networking/` (plus
      power-off `E5 1D` and the raw-fallback index 9 → `41 10`; the latter's
      meaning was settled on 2026-09-19 — see "Protocol verification").
- [x] **1.1.2** — **Drop the per-index source names from `source_mapping.dart` /
      `command_payloads.dart` comments and rename `phonoStatusIndex`** —
      names are per-unit (`docs/protocol.md`, "Names are per-unit"). Done
      2026-09-19 (`hardcodedSelectStatusIndex`; debug-screen label and test
      comments de-named too; `status_packet_test.dart` fixture names kept
      on purpose).
- [x] **1.1.3** — **Make the ceiling a required parameter** on `setVolume` /
      `encodeCommandWord` with an explicit "none" value (checklist item
      28). Done 2026-09-20 with 3.4.7 / 3.4.8 (the analyzer proves the
      parameter is required; the probe tool's cross-check passes −15
      explicitly to keep its golden bytes).
- [ ] **1.1.4** — **Encode the select-source fallback as `bfloat16(index)`.**
      ✔ 2026-09-19 (`docs/protocol-verification-2026-09-19.md`): the
      payload is the top 16 bits of `float32(index)`, truncated by the
      amp; the current `0x4000 | (i << 5)` + `>> 1` formula only
      coincides with that for 6–15, and indices 16–29 encode as 32.0,
      36.0, … — silent no-ops. Keep the seven pinned table byte pairs
      (confirmed on two amps) and the index-1 literal; replace only
      `SourceMapping.encodeSelectPayload`'s general case, pin
      `16 → 41 80` and `29 → 41 E8`, and retire the `>> 1` comment. Not
      confirmable on the owner's unit (no enabled slot ≥ 6) — say so in
      the test name.

## Protocol verification (unnumbered, runs alongside)

Live run done 2026-09-19 against the owner's amp from the dev machine —
method, safety envelope, per-trial results and raw log in
`docs/protocol-verification-2026-09-19.md` (+ `docs/captures/`,
`tool/protocol_probe/`). No root pcap was possible; the listener read
the raw datagrams directly, which covers the inbound side.

- [x] **Confirm counter-caveat behavior.** ✔ The amp ignores both counters
      entirely: frozen (0,0) 6/6, arbitrary/decreasing/mismatched 6/6,
      byte-identical duplicates 4/4. No contiguity, no de-duplication, no
      persisted counter needed. The double send is not needed on Ethernet
      (20/20 single sends). Also found: CRC and magic bytes *are* checked
      (bad CRC 0/5), the zero padding is not (14-byte packet applied).
- [x] **Confirm fallback-to-raw-index behavior for unmapped sources.** ✔
      The payload is `float32(index)` truncated by the amp (3.0 → 3,
      1.5 → 1, 2.75 → 2, NaN/−1.0 → 0). "Index 9 showed Air" was a
      per-unit alias slot 9 → 14 (3/3 from three start slots); every other
      disabled/out-of-range index was a no-op (12/12). The general
      formula is wrong for indices ≥ 16 → Task 1.1.4. The enabled-but-
      unmapped case remains untestable on this unit (only 0–4, 14 enabled).
- [x] **Adaptive retry under Wi-Fi loss.** Decided 2026-09-19: **keep the
      fixed double send, no adaptive retry.** Wi-Fi dropped 2/20 single
      sends and 0/10 double sends; the confirmation channel (3.1.x) is the
      recovery path for the residual case.
- [ ] **Measure broadcast delivery over Wi-Fi on the phones.** The
      desktop's Wi-Fi adapter received only 49 % of the amp's 5 Hz
      broadcasts, 8–164 ms behind the wired copy. If the Galaxy S25 / iPad
      see anything like that, Task 3.1.x's 400 ms window must assume a
      confirmation can simply never arrive (fall back to the optimistic
      value, don't wait forever) and the 8 s staleness rule is fine.
      Method: `tool/protocol_probe/listen.py` ported to a debug screen, or
      just the Task 1 debug scaffold counting packets per 30 s. Data point
      2026-09-21 (Task 3.5.2, change-only trace so not a packet count):
      in six 30 s post-boot windows the S25 missed the +200 ms broadcast
      twice, never a first On packet, and never went "Not connected".
- [x] **Accepted limitation (owner, 2026-09-20): a power-on started by
      another client shows as "Off" until the amp reports On.** The phone
      cannot see another client's unicast command, and the amp's broadcast
      is not believed to signal a boot in progress, so there is nothing to
      recognise; the display flips to On the moment the amp says so and
      the post-boot follow-ups (3.2.5) still run. Reopen only if a raw
      capture of the unexplored bytes around offsets 562–565 during a boot
      ever shows a difference from idle Off.
- [ ] **Re-run the source probes on a second unit** if one is ever on the
      LAN: an enabled slot ≥ 6 confirms the float fallback; sending 9.0
      tells whether the 9 → 14 alias is firmware-wide or per-unit.

## Task 2.0.x — Control screen UI from the mockups (UI only)

Adopt the design mockups for the **Control screen only** (built from
v19; the v36 pass is 2.0.15, the v39 update 2.0.19, the v40 rhythm sync
2.0.21 — **the current files are**):

- Android: `design/mockups/devialet_remote_mockup_Android_v40.html`
- iOS: `design/mockups/devialet_remote_mockup_iOS_v40.html`

Only this block and `CLAUDE.md` name the *current* mockup; every other
version number in this file and in code comments is provenance (the
version that introduced a rule) and stays as history when the mockup is
bumped. The guards live in `test/ui/mockup_test.dart` (version-agnostic
name for the same reason).

Scope: widgets, layout, theming and every *visual state* of the Control
screen, driven by a debug/fake state object — **no protocol wiring, no
state owner, no persistence**. The mockups are "Control only" in the sense
that the Kotlin app's Control/Sound tab switcher is gone (the Sound tab is
not planned, above). Note that both mockups *also* contain a Settings page
(push-navigated from the header gear), a Theme bottom sheet and an About
group; those are **out of scope here** and belong to Task 3.4.x.

Per-variant through `uiVariantProvider` (CLAUDE.md, "Runtime UI variant
switching"); conventions differ, behaviour below does not.

**Built 2026-09-19** (2.0.0–2.0.12; 2.0.13 is the owner's hands-on check).
Code map: `lib/domain/control_view_state.dart` (+ `_provider.dart`, the
fake owner), `lib/config/window_class.dart`, `lib/ui/theme/`,
`lib/ui/platform/`, `lib/ui/widgets/`, `lib/ui/control/`,
`lib/ui/debug/debug_state_driver.dart`; 133 tests under `test/`.
**Owner decisions taken while planning, 2026-09-19:**

- **A silent amp is presented exactly like "no amplifier selected"** —
  discovered list emptied, active = None, footer "Not connected". A phone
  cannot tell an amp that stopped broadcasting from one that is unplugged,
  so there is no third "Not responding" presentation (2.0.8 / 2.0.10 below
  were rewritten accordingly). The *persisted* selection must still
  survive silence so the app reconnects by itself when broadcasts resume —
  Task 3.0.8.
- Fonts are bundled (`assets/fonts/`, OFL notices registered with
  `LicenseRegistry` in `main.dart`); the iOS variant keeps the system font
  for body text, as the mockup intends.
- Full static sheets (amp sheet with the inline manual-IP view, source
  sheet with empty state); the dial has a rotary drag on the ring band.
- No v20 mockup pass: after the decision above the only deltas from v19
  are two text substitutions ("Muted" readout, footer status word).

- [x] **2.0.0** — **Adaptive layout from the first commit (phones + tablets).** The
      mockups describe the *compact* width class only. Build the Control
      screen against a width-class value (compact / medium / expanded)
      read from the window, not from `Platform`/device type, and give
      every width class a layout: compact = the mockup verbatim;
      landscape on a phone treated as compact-height rather than ignored;
      medium/expanded = an **interim** centred, max-width content column
      so the dial and buttons don't stretch across a tablet. The real
      expanded layout is **two-pane** (owner decision 2026-09-19, see
      Task 3.11.x) and is deliberately *not* built here: it needs its own
      mockup pass, and tablet verification is deferred because loading
      the iPad is a whole process the owner doesn't want early in the
      port. The width-class plumbing must still be in place now so 3.8.0
      is a layout swap, not a refactor. Done: `WindowClassScope`
      (Material 3 breakpoints 600/840, 480/900) installed in the app
      `builder:`; the interim column is one `ConstrainedBox`
      (`kInterimColumnMaxWidth = 480`, `control_layout.dart`) that 3.11.1
      swaps out; compact height scrolls. Sheets cap their width the same way.
- [x] **2.0.1** — **Window-size changes at runtime** (rotation, iPad Split View /
      Slide Over / Stage Manager resize, Android split-screen) must
      rebuild the layout without losing state: open sheet, in-progress
      dial drag, draft settings survive a width-class change (the Kotlin
      app handled rotation itself via `configChanges`; Flutter has no
      equivalent free pass — `docs/app-overview.md`, "Screen/orientation
      handling"). Done: fake state lives in Riverpod, the live drag value
      in `ControlScreen`'s state, sheets are Navigator routes with their
      own state; `test/ui/control_screen_resize_test.dart` resizes
      390×844 → 1024×768 with a sheet open, mid-drag, and with a typed IP.
- [x] **2.0.2** — **Header / amp card:** whole row is the tap target; shows
      `model ?? name` with the IP and a static status word; nothing-selected
      header reads "No Amplifier" / "Tap to connect". Device dot states:
      connected / booting (pulsing amber) / off / none (plain outline).
      Done (`device_card.dart`; "Connected" stays while the amp is Off —
      it describes the UDP link, per the mockup comment).
- [x] **2.0.3** — **Amp bottom sheet (static):** "None" is always the first row, above
      a divider, italic, plain outline dot; strings verbatim from the
      Android app: "None" / "Don't connect to any amplifier". Rows show
      `model ?? name` with a " · name unresolved" tag when only the UDP
      name is known; selected row has a check. Manual-IP entry view kept
      inside the same sheet. Done (`amp_sheet.dart`; IPv4 validated
      before "Connect" is enabled; "‹ Back to list" returns to the list —
      not in the mockup, needed because the scrim is the only other exit).
- [x] **2.0.4** — **Volume dial + VOL −/+ buttons + dB readout.** Slider hit target
      larger than the painted track; the readout binds to the live drag
      value. The mockup's dial range is hardcoded −60..−15 and the arc
      geometry is ported from `VolumeDialView.kt`; the *range* must come
      from the floor/ceiling settings once Task 3.4.x exists — don't bake
      the mockup's numbers in (checklist items 14, 15). Done: range is
      `floorDb`/`ceilingDb` on the state (fixture −60/−15; a −50/−20 test
      proves nothing is baked); ring band from r 63 to the box edge is the
      hit target, the centre readout is not; bottom 90° dead zone snaps
      on press, is ignored mid-drag; the dial claims the pointer eagerly so
      the scroll view never steals a vertical drag; 0.5 dB display steps.
- [x] **2.0.5** — **Mute control:** toggle with label Mute/Unmute **and** a glyph that
      follows state; readouts show the word "Muted" instead of a dB value
      when muted. Done.
- [x] **2.0.6** — **Power control and Booting presentation:** spinner replaces the
      power glyph, label "Powering on…", pulsing amber status dot, header
      subtext "Booting…", power control genuinely inert while Booting.
      Done (the fake owner has no boot timer: Booting stays until the
      debug bar moves on, so tests are deterministic; Task 3.2.x drives
      it from the amp).
- [x] **2.0.7** — **Buttons whose label changes** ("Mute"↔"Unmute", "Power
      On"↔"Powering on…") sized to their widest possible content, measured
      on the Galaxy S25, so nothing shifts on toggle (checklist item 16).
      Done structurally (`WidestLabel` lays every candidate out invisibly;
      `test/ui/widest_label_test.dart` pins icon position and label width
      across states). The on-device measurement is 2.0.13.
- [x] **2.0.8** — **Disabled presentation:** Off / Booting: every non-power control
      dimmed to **0.4** opacity, disabled, **keeping last-known text**
      ("−25.0", "Unmute", source name). No amp (incl. a silent amp, see
      the decision above): dial group 0.4, whole action row 0.4 (power
      included), source trigger 0.5 **still tappable** (opens the empty
      state), dB shows "—" with the unit hidden but its space kept. Done
      through one `DimmedGroup` at four gate points, gating derived from
      `ControlViewState`'s getters so every input path is covered
      (checklist item 6; `test/ui/control_screen_states_test.dart`).
- [x] **2.0.9** — **Source row:** closed row shows an icon chip following the active
      source's glyph, eyebrow label, name (elided — "Chromecast Audio
      Extra Long" is the test case), caret; placeholder "No source". Open: a
      bottom sheet over the row (nothing below moves), active row
      highlighted with a check; empty state when there are no sources.
      Done. Glyphs are the mockup's Unicode symbols keyed on the live name
      (`source_glyphs.dart`); coverage on device is a 2.0.13 check.
- [x] **2.0.10** — **Footer status:** static "Connected" / "Not connected" (the
      third word was dropped with the silent-amp decision above; the
      mockup's hint sentence was replaced, owner decision 2026-09-19).
      **Superseded by v36 (2.0.15, 2026-09-22):** both mockups dropped
      the footer slot altogether, so the status word went with it; the
      device card's subtitle ("· Connected" / "Tap to connect") is the
      one place the link state is shown.
- [x] **2.0.11** — **Theme tokens** (copper/graphite palette, dark + light variants)
      lifted from the mockup CSS into one place so Task 3.4.x's Theme
      setting and Task 5.0.0's icon can reuse them. Fonts in the mockups
      are Google-hosted (Space Grotesk / JetBrains Mono / Inter) — bundle
      what ships or pick platform fonts; an asset outside the bundle
      renders as nothing (checklist item 18). Done: `AppTokens.dark/light`
      (+ `ThemeExtension`), `AppTypography`, `AppTheme.of(context)`;
      brightness follows the OS through the one `builder:` in `app.dart`,
      which is where 3.4.x's Theme setting plugs in. Not ported: the light
      theme's gradient "foil" text on the wordmark and dial value (flat
      copper instead) — revisit in the light-theme eye check.
- [x] **2.0.12** — **Debug state driver:** a debug-only control (not a hidden gesture)
      that cycles the fake state through connected / off / booting /
      not-responding / not-connected / muted so every state above can be
      eyeballed on the Galaxy S25 without an amp. Done: in-flow bar under
      the footer, `kDebugMode` only, ◀ / ▶ plus a "Net" button that pushes
      the Task 1 network test screen. **Since 3.0.x the bar drives a
      simulated amp** (`lib/domain/debug/simulated_amp.dart`, TEST-NET IPs,
      real ingest path, opt-in on first tap); **since 3.2.x it is
      command-aware** (boots in 16 s, misreports −42 until a volume command,
      drops early volume commands), so the whole boot loop can be soaked
      without hardware. "Not responding" takes the real 8 s.
- [ ] **2.0.13** — **Hands-on check on the Galaxy S25** in both UI variants, report
      recorded here (checklist item 23), before the task is called done.
      The interim expanded column is checked on an Android tablet
      emulator or a resizable desktop window only — **no iPad load in
      this task**. Measured row heights and button widths are per width
      class (checklist items 14, 16). Checklist for the soak (both run
      configs, `UI_VARIANT=android` and `=ios`):
      - cycle all six scenarios with the debug bar; compare each against
        the current mockup (v40) side by side (fonts, sizes, spacing,
        colours);
      - glyph coverage of ◉ ◫ ◍ ◈ ◐ ◇ ⌨ ✓ in the trigger and the sheets
        (tofu → replace with painted icons in `stroke_icons.dart`);
        ✔ 2026-09-21 S25 screenshots (Android variant): the source
        sheet's ◉ ◫ ◍ ◈ ◐ ◇ ✓ all render; ⌨ and the iOS variant unchecked;
        since 2.0.16 **all six** are painted, not characters (on the
        S25 ◉ ◍ ◈ rendered tiny and ◇ large — checked 2026-09-23, both
        themes, uniform now), and the light theme's gold glyph gradient +
        drop shadow are ported;
      - dial: drag feel around the ring, the bottom dead zone, a press on
        the readout doing nothing, −/+ taps; readout following the finger;
      - press feedback: Android ripple, iOS spring scale; the power
        button's red/green press tint;
      - booting dot pulse (1.1 s) and spinner (0.7 s) timing;
      - sheets: Android gradient panel vs iOS frosted panel and its
        scroll performance; scrim tap dismisses; manual-IP keyboard type
        and the "Connect" enable rule;
      - light theme via the OS toggle (flat copper text where the mockup
        has foil gradients — decide whether to port them). **Owner note
        2026-09-20:** the dial's centre volume number is too dark in the
        light theme; accepted for now, fix in a later polish pass (the
        mockup's light dial value is a `#c17f0e → #f0c873` gradient, which
        was not ported);
      - ✔ the phone must not rotate (portrait lock) — verified on the S25
        2026-09-19; a resize with a sheet open and mid-drag is checked on
        the tablet emulator instead;
      - tablet emulator / resizable window: the centred 480 column, the
        sheet width cap, phone-landscape scrolling;
      - record measured row heights and label widths per width class
        here; port any measured value that disagrees with the mockup.
      - **S25 soak 2026-09-19 (owner):** everything renders fine in both
        variants. The column does not quite fit the screen *with the
        debug bar* (≈ 66 dp: 32 dp chips + 16 dp padding + 18 dp margin).
        Resolved in 2.0.21 (2026-09-23): with the bar gone the column
        still overshot the S25 by 18 dp; the vertical rhythm was
        tightened by 30 dp (dial stays 220 dp) and it fits with ≈ 12 dp
        to spare
        (checklist item 14: measure, don't guess).
- [x] **2.0.14** — **Wordmark foil sheen (owner request 2026-09-22):** the
      "DEVIALET" wordmark / eyebrow in the **light theme** gets the
      mockups' gradient clipped to the letterforms — `#a8710b → #d99a1f →
      #fbe6ab`, darkest on the left, brightest on the right (both v19
      mockups, `.phone.light .wordmark` / `.nav-eyebrow`; the mockup
      rejected the same sheen on the dB readout as too busy). Dark theme
      stays flat copper, as mocked. Done 2026-09-22:
      `AppTokens.wordmarkGradientColors` (null in dark) + a `ShaderMask`
      in `ControlHeader`; `test/ui/wordmark_sheen_test.dart`; checked on
      the S25 (light, Android variant).
- [x] **2.0.15** — **v19 → v36 mockup pass (owner request 2026-09-22),** both
      variants, Control + Settings + sheets. Ported 2026-09-22
      (`test/ui/mockup_test.dart`, 23 tests; nine guards counter-run
      red; 331 tests green):
      - light accent `--copper-bright` `#d98c0f` → `#c79a2e` (token +
        Cupertino primary); wordmark 13 → 15 (Android), eyebrow 12 → 14
        (iOS);
      - header icon buttons are bare glyphs in a 44 dp target with a
        neutral press disc (`HeaderIconButton`; gear glyph 23 dp, the new
        cog outline in `stroke_icons.dart`; Android Settings back arrow
        30 px). The mockup's negative margins (gear −10 right, back arrow
        −12 left) are painted with an `OverflowBox`; **the overhang is
        not tappable** (hit tests stop at the content edge), so the live
        target is 34 × 44 / 32 × 44 dp — accepted, note if it bites in
        the soak;
      - source card: no "Active source" eyebrow, name 18/600; control
        footer and settings footer lines removed (see 2.0.10);
      - source sheet: outlined cards (1.5 px, r16, 8 apart), mono "kind"
        label (`sourceKindFor`, the mockup's six names; **an unknown name
        gets no label** rather than a guess), copper outline on the
        active card, static corner arcs (`SheetArcs`), painted Spotify
        glyph (`SourceGlyph`); light theme glyphs gold-gradient + shadow
        (in v19 too — never ported until now);
      - amp picker: animated "listening" arcs next to the subtitle
        (`ListeningArcs`, 1.8 s, 250 ms stagger, list view only; static
        under reduced motion). Tests open it with `openAmpSheet` /
        `settleSheet`, not `pumpAndSettle` (never settles);
      - contrast (v26): sheet subtitles, amp-row subtitles and settings
        descriptions `textFaint` → `textDim`;
      - settings (v28/v29/v32): stepper values, entry field and the
        selected step are plain `text` colour (the `numericAccent` token
        is gone); the accent moved to the section headings — light a
        gold gradient, dark flat copper, weight 700, Settings only
        (`SectionLabel(accent: true)`);
      - iOS Settings back control is the plain text colour in both
        themes (v30);
      - **not ported / n.a.:** the selected step's declared weight 700 —
        JetBrains Mono is bundled up to 600 here *and* in the mockup's
        Google Fonts link, so the browser renders 600 too; kept 600
        (checklist 15). iOS status bar "plain text in both themes" (v31)
        is the OS's own bar, nothing to do in-app.
      - [ ] **Eye check on the S25, both variants, both themes** (the 2.0.13
        list plus: gear/back-arrow press disc and alignment, source cards
        and kind labels, corner arcs clipping at the sheet edge,
        listening-arc timing, settings heading gradient at 11 px). Source
        glyphs: done in 2.0.16.
- [x] **2.0.16** — **Painted source glyphs (owner request 2026-09-23).** The
      v36 mockup's Unicode ◉ ◫ ◍ ◈ ◐ ◇ came out of the S25's font at
      wildly different sizes (◉ ◍ ◈ tiny, ◇ large, painted ◐ in between),
      in the sheet and the trigger card alike. All six (plus the "–"
      placeholder) are now painted by `SourceGlyphPainter` in the 20-unit
      box the v36 Spotify SVG used (7.6-radius ring / 15.2-wide square or
      diamond, 1.6 stroke), so they share one size: `size × 1.05` (15.75
      in the sheet, 16.8 in the trigger). `sourceGlyphFor` keeps the
      character table as documentation only. Verified 2026-09-23 on the
      S25 (Android variant, dark + light: gradient and shadow on all six).
      Guard: `mockup_test` asserts every card's and the trigger's
      paint box is the shared size and no glyph character is a `Text`;
      counter-run red by oversizing the Air glyph. **Mockup deviation
      (checklist 15):** the mockups still declare the characters — in a
      desktop browser they render evenly, so the mockup is left as is;
      port SVGs there only if a later mockup round touches the glyphs.
      **Same day, same fix for the theme sheet** (owner screenshot: ◐ ☾ ☀
      tiny too): `ThemeGlyph` / `ThemeGlyphPainter` (half ring, crescent,
      sun) in the same box, and the gold mask + shadow wrapper extracted
      into `lib/ui/widgets/painted_glyph.dart` (`PaintedGlyph`,
      `GlyphPainter`) so both sheets share it. Verified on the S25 in both
      themes; guard + counter-run (undersized Dark glyph) in
      `mockup_test`.
      **Round three, same day (owner screenshots), all verified on the S25
      in light:** (a) the sun's gold radiates from its centre
      (`PaintedGlyph.gradientCenter`/`gradientRadius`, `ThemeGlyph` passes
      centre + 0.5 for Light only — the off-centre mockup gradient lit one
      ray more than the rest); (b) the selected-row tick is painted
      (`CheckMark`, 18 px, 2-unit stroke, flat copper) in the theme, source
      and amp sheets — the 14 px ✓ character didn't read as a highlight;
      (c) `DeviceDot.defaultSize` 10 → 13 (card + amp list; the mockup's
      10 px read as a speck next to the 15.75 px glyph boxes) and the amp
      row's leading slot 12 → 16; (d) the Control screen's VOLUME / SOURCE
      headings take Settings' gold gradient / flat-copper 700
      (`SectionLabel(accent: true)`) — the mockup still declares them
      faint there, checklist 15 deviation. Guards for all four in
      `mockup_test` (337 green); counter-runs red for the Source
      accent and the sun centring.
- [x] **2.0.17** — **Sheets lift above the keyboard (owner bug report
      2026-09-23).** The manual-IP entry sat fully under the S25's keyboard:
      neither modal route pads for `viewInsets` (Material's `useSafeArea`
      is top-only) and `_SheetFrame` padded only `viewPadding.bottom`.
      Fixed in `adaptive_sheet.dart` for both variants: the panel reserves
      `max(viewPadding.bottom, viewInsets.bottom)` (the keyboard covers the
      nav-bar strip, so never both) and its content cap becomes
      `min(72 % of the window, what's left above the keyboard − top safe
      area − 24)`, so the field scrolls into view instead of the sheet
      growing off-screen. Verified on the S25 (light, Android variant):
      field, hint and Connect all visible with the number pad up. Guard:
      `sheets_test` "keyboard" group, both variants, with a 320 px fake
      inset; counter-run red by dropping the inset from the reserve.
- [x] **2.0.18** — **Painted "Enter IP Manually" glyph, box removed.** The
      row's ⌨ rendered as a colour emoji on Samsung, inside a bordered box
      the mockup never declared (`.source-option .source-icon` has no
      border) and that clashed with the bare header icons. Candidates
      (keyboard / keypad / entry field) previewed to the owner 2026-09-23;
      **pick: A, keyboard, gold like the other glyphs** (the mockup's
      `textDim` for this row is overruled — owner decision, checklist 15).
      `ManualEntryGlyph` / `ManualEntryGlyphPainter` through
      `PaintedGlyph`: a 15.2 × 10.4 slab filling the ring's footprint (so
      it carries the dot's mass), four key ticks, a space bar; copper in
      dark, gold gradient + shadow in light; bare `SizedBox` chip. Guard
      in `mockup_test` for both themes (size, mask/shadow, no ⌨, no
      bordered chip).
      **Optical sizing pass (owner, same day):** "same box" was the wrong
      target — an outlined shape reads lighter than a filled disc of the
      same box. Measured on the S25 (light, 1080 px wide) from
      screenshots, gold-ink bounding box / ink pixels:
      amp dot 40 × 40 / 1236; keyboard as first drawn 40 × 30 / 630; after
      `PaintedGlyph.opticalScale` 1.15 + a taller slab (11.2 units)
      46 × 36 / 842 — reads level. Also: every amp row shares one 20 dp
      leading slot (`_AmpRow.leadingBox`, the keyboard row too), so all
      titles start at the same x (measured 184 px for None / amp /
      Enter IP; guard asserts one x across the rows, counter-run red at
      {60, 72}); and the trailing `›` is painted (`ChevronMark`, 18 px box
      like the tick; 13 × 21 px as a character → 21 × 38 px painted,
      against the tick's 42 × 32) on the amp row, the source trigger and
      the settings rows.
- [x] **2.0.19** — **Owner's mockup update, 2026-09-23 (four changes;
      mockups v39, `design/mockups/*_v39.html`, committed by the owner).**
      (a) Source trigger name 18 → 15/600, the amp name's size (18 drew
      disproportionate attention); guard also asserts equality with the
      device-card name. (b) Keyboard glyph `opticalScale` 1.15 → 1.25:
      measured 50 × 38 px / 948 ink against the dot's 40 × 40 / 1236 — a
      touch past the dot, as the update has it; still inside the 20 dp
      slot (19.7). (c) Manual-entry view: the "‹ Back to list" line is
      gone; `SheetScaffold.onBack` puts a bare back chevron (44 dp
      `HeaderIconButton`, overhang −12, `ChevronMark` flipped, `textDim`)
      beside the title and indents the subtitle under it. The v36
      mockup's boxed `.sheet-back` is **not** ported — the owner dislikes
      boxed icons (checklist 15, same call as the gear). Keyed
      `ControlKeys.sheetBack`. (d) `sourceDisplayName`: the word "Air" is
      always shown as "AIR" (Devialet's acronym, Asynchronous Intelligent
      Route; owner decision) — word-bounded so AirPlay is untouched; the
      raw name stays the protocol/matching key. Guards in `sheets_test`
      (back control geometry, no chip, AIR in trigger + sheet),
      `mockup_test` (15 px), `source_glyphs_test`; counter-runs red
      for the back control and the AIR mapping. Verified on the S25 in
      light: Control, amp picker, entry view with the keyboard, source
      sheet.
      (e) Missed in the first pass, added the same day: the light theme's
      dB readout takes v39's brighter two-stop gold
      (`dialValueGradientColors`, `#dca136 → #f3cf7c`, `.phone.light
      .dial-value` rule 10) clipped to the digits — the readout had been
      flat `copperBright` since v19 (v36's `#c17f0e → #f0c873` was never
      ported). Dark unchanged: flat copper + glow. Guard in `mockup_test`.
- [x] **2.0.20** — **Debug state driver removed (owner, 2026-09-23).** The
      bar under the Control column (2.0.12: cycle six synthetic scenarios,
      `PREFS OFF` chip, "Net" to the Task 1 test screen) made sense before
      the real wiring existed; now every state is reachable by using the
      app, so it is gone: `lib/ui/debug/debug_state_driver.dart` deleted,
      its keys and its two tests dropped, `widget_test` asserts its
      absence. `SimulatedAmp` stays (TEST-NET routing in `main.dart`,
      its own tests, the `DebugScenario` fixtures every UI test uses).
      **Follow-up, same day (owner):** `lib/ui/debug/debug_network_screen.dart`
      (the Task 1 manual UDP screen) was left unreachable by this; deleted
      too — a manual IP goes in through the amp picker now, and
      `tool/protocol_probe/` covers dev-machine probing. `lib/ui/debug/`
      is gone with it; `lib/domain/debug/` (the simulated amp) stays.
- [x] **2.0.21** — **Control column fits the S25 without scrolling (owner,
      2026-09-23).** After 2.0.20 the column still scrolled by ≈ 18 dp
      (owner's top/bottom screenshots: 54 px at 3.0). Measured, not
      guessed: a fit guard at the phone's real geometry (`wm size`
      1080 × 2340, density 480 → 3.0, `dumpsys window` status bar 103 px /
      nav bar 45 px → 730.7 dp available) with the **bundled fonts loaded**
      (`test/ui/support/app_fonts.dart`; the test framework's placeholder
      font made the same column 55 dp taller, so any fit assertion needs
      the real faces) reported 18.3 dp of overshoot — the phone's number.
      Trim, Control screen only (`control_layout.dart` constants; Settings
      keeps the mockup rhythm): header bottom 20/18 → 16/14, first
      section top 22 → 18, later sections 26 → 20 (`SectionLabel.top`),
      dial padding 8/4 → 4/0, volume buttons top 18 → 14, action row top
      22 → 18 = 30 dp; content padding 6/28 and the 220 dp dial unchanged.
      Result: column 715 → 685 dp, ≈ 12 dp slack; on the S25 a swipe up
      changes zero pixels. Guard `control_screen_fit_test` (no scroll
      extent + ≥ 8 dp slack); counter-run with the mockup values red at
      18.3. **Mockup deviation (checklist 14/15), closed 2026-09-24:** v39
      declared the old rhythm — its phone frame is taller than the S25's
      usable area. The owner's **v40** (commit 39b71b5, 2026-09-23,
      `design/mockups/*_v40.html`) ports the six `control_layout.dart`
      constants into both variants, scoped to the Control screen
      (`.screens .screen:first-child …`: header 16 / eyebrow 14, first
      section 18, later sections 20, dial 4/0, VOL buttons 14, action row
      18); Settings keeps the original rhythm. Mockup and app agree again;
      2.0.22's flexible ranges still go into the round after. iOS geometry not
      measured (no device); the iPhone-15 class has ≈ 32 dp more usable
      height, so it fits by arithmetic, unverified.
- [ ] **2.0.22** — **Control screen adapts to shorter phones (owner
      request 2026-09-23).** 2.0.21 made the column fit the S25 with fixed
      spacing constants tuned to its 730.7 dp of usable height; a shorter
      phone still scrolls, and a taller one gets empty space at the bottom.
      A control screen should fit on one screen wherever it reasonably can
      (a scrolling remote feels broken), so the layout adapts to the
      available height instead:
      - **Flexible gaps:** the vertical rhythm in `control_layout.dart`
        becomes a range per gap — a floor (tightest acceptable) and a
        ceiling (the mockup's value) — and leftover height is distributed
        between them. Control sizes stay fixed; only the space between
        them flexes.
      - **Hero element scales:** the dial sizes itself from the remaining
        height within a min/max (220 dp max as today; 180 dp min is a
        stated guess, checklist 14). Ring stroke, readout type and the
        drag hit band (`dialHitTest`'s r 68 inner edge) scale with it, so
        the gesture feel stays proportional.
      - **Never shrink touch targets:** VOL ±, mute, power and the source
        card keep their sizes (≥ 48 dp Android / 44 pt iOS minimums).
      - **Scroll stays as the last resort** for screens below the floor;
        the `SingleChildScrollView` is not removed.
      - **Reference screens (checklist 14, measure):** S25 (730.7 dp,
        must look unchanged from 2.0.21), a small phone (≈ 640 dp usable,
        compact Android; the iPhone SE's 667 pt minus its status bar is
        the iOS equivalent) and a tall phone (≈ 800 dp, gaps and dial
        stop at their ceilings rather than stretching). Extend
        `control_screen_fit_test` into a table over these heights with
        the bundled fonts loaded; counter-run with the fixed 2.0.21
        constants restored (small screen must go red).
      - Settings stays a scrolling list: it's a content screen, where
        scrolling is expected.
      - Fold the floor/ceiling values and the dial range into the next
        mockup round, so a later mockup sync doesn't undo them.
      Scope: compact width, portrait phones only; expanded width is Task
      3.11.x. Hands-on check on the S25 in both variants; no small
      physical phone exists, so the small-screen case is verified by the
      fit test and an emulator.

## Task 3.0.x-3.3.x — Software architecture: state owner + persistence layer

**Design first, then implement the core.** A written design (in
`docs/app-overview.md` or a new `docs/architecture.md`) precedes any
control wiring, because checklist items **1, 2, 3 and 7** are all owner-
level concerns: a late broadcast can only be masked correctly by the one
place that knows *when* it sent; two surfaces guessing independently will
diverge; rapid repeat only works if the optimistic write is synchronous in
the owner; and a post-boot report is only trustworthy after the owner has
set a value and waited. Wiring buttons before this exists reintroduces
gotchas #1/#2 one input at a time.

### 3.0.x — State owner (Riverpod)

- [x] **3.0.0** — One Riverpod-owned live amp state, injected into every surface as a
      *required* dependency; views never keep private copies of
      volume/mute/ip/power (checklist items 2, 5). Done 2026-09-19:
      `AmpStateOwner` / `ampStateProvider` (`lib/domain/amp_state_owner.dart`),
      the UI reads the derived `controlViewStateProvider`; the fake notifier
      is gone. Design: `docs/architecture.md`. The dial's in-progress drag
      value is gesture state, not a copy (TODO 3.6.4).
- [x] **3.0.1** — **Confirmed-vs-optimistic split:** the owner exposes both a
      *displayed* value (optimistic, masked) and a separate unmasked
      **confirmed** value taken from the raw status byte; exact equality,
      no epsilon (`docs/protocol.md`, status notes). Feedback (Task 3.10.x)
      derives from confirmed state, never from the gesture (checklist
      item 25). Done 2026-09-19: `confirmedAmpStateProvider` /
      `ConfirmedAmpState` (carries `volumeRaw`, now parsed by
      `DevialetStatus`).
- [x] **3.0.2** — Optimistic writes are **synchronous, before the async send**, so each
      step accumulates on the stored value (5 taps 10 ms apart = 5 steps);
      rollback on send failure (checklist item 3; `docs/protocol.md`
      reconciliation #6). Done 2026-09-19 structurally: intents arm the
      pending slot, then `await` an `AmpCommandSink`, clearing the slot on
      a throw. **Sends are `NoopCommandSink` until Tasks 3.5–3.9** (owner
      decision: display-only first), so an optimistic change reverts after
      400 ms on a real amp.
- [x] **3.0.3** — All timers on one monotonic clock source; staleness `online =
      last_seen < 8 s` on a 1 s tick. Done 2026-09-19 (`MonotonicClock`,
      `staleTickProvider`; deadlines are compared on every ingest and tick,
      no per-field timers).
- [x] **3.0.4** — Status broadcasts are **triggers, not truth**: re-read state after a
      change rather than trusting a single field; never assume fields of
      one update arrive atomically (checklist items 12, 13). Done
      2026-09-19 by construction: every ingest replaces the whole `status`
      and the view is re-derived from it; there are no per-field handlers.
- [x] **3.0.5** — Only the broadcast whose sender IP matches the selected amp updates
      live control state; every broadcast feeds the discovery map (Task
      3.9.0 owns the map's semantics). Done 2026-09-19; the transport now
      carries the sender (`UdpDatagram`, `AmpStatusReport`).
- [ ] **3.0.6** — *(open — not touched by 3.0.x; sheet-visibility rules come with
      3.8.2 / 3.11.x)* **No "one screen at a time" assumption.** On expanded widths
      Control and Settings (or Control and the amp/source lists) can be
      visible and interactive *simultaneously*, and two windows of the
      app can exist on iPadOS / Android multi-window. So: every
      cross-view value (volume, mute, power, source, selected amp, the
      settings draft) has exactly one owner and no view-local copy
      (checklist item 2); sheet/list open-closed state and the "reset
      sheets when the screen is left / power leaves On" rule (Task 3.8.2)
      are owner-driven and expressed in terms of *what is visible*, not
      of navigation routes; a settings Apply must reflect on a Control
      pane that never left the screen (checklist item 11's re-trigger).
- [ ] **3.0.7** — *(open — `WindowClassScope` still reads `MediaQuery` in the app
      builder; a provider/define override is the remaining piece)* **Width class is injected like the UI variant:** one
      `windowSizeClassProvider` (or equivalent) derived from the window,
      overridable in tests and by a debug define, so layouts and any
      per-width constants read it rather than `MediaQuery` ad hoc, and
      so a phone-width window on a tablet gets the phone layout by
      construction (checklist item 28).

- [x] **3.0.8** — **A silent amp is presented as "no amplifier" but the
      selection is not forgotten** (owner decision 2026-09-19, Task 2.0.x):
      after 8 s without a broadcast the owner emits the not-connected
      shape (`ControlViewState.selectedAmp == null`, list pruned), while
      the *persisted* selection (3.3.x) stays untouched, so the next
      broadcast from that IP reconnects without a tap. Distinct from the
      user choosing "None" (checklist items 4, 26). Done 2026-09-19:
      "pruned" = the list shows online amps only, the map never evicts
      (KDE); `selectedIp` is kept and exposed on the view. Caveat for
      3.9.x: while the chosen amp is silent the sheet highlights "None";
      decide whether to render an offline row from `selectedIp` instead.

- **S25 soak 2026-09-19 (owner):** the real amp (192.168.0.22) appears in the
  amp sheet next to the simulated ones, named from its UDP broadcast — no
  model name until Task 3.9.5 resolves it over mDNS, as expected.
- [ ] **3.0.9** — `ControlViewState.volumeDb` is non-nullable and the derivation
      fills it with the floor when there is no amp (a sentinel the UI never
      formats because it checks `hasAmp` first). The honest type is
      `double?`; change it together with the readout path in
      `control_screen.dart` when a task next touches that file.

### 3.1.x — Pending-command mask + confirmed channel

- [x] **3.1.0** — 400 ms pending mask in the state owner (not in widgets): after a
      local command the local value is authoritative until a broadcast
      exactly matches it (confirmed) or 400 ms elapse (fall back to the
      amp's value). A newer command replaces the value and re-arms the
      deadline. Covers volume, mute, power, source in one place (checklist
      item 1). Done 2026-09-19 (`PendingValue`, `TrackedAmp.resolvePending`,
      `docs/architecture.md` §8).
- [x] **3.1.1** — Unit tests with `FakeUdpTransport` reproducing gotchas #1/#2 (late
      pre-change broadcast) and proving the mask absorbs them; prove the
      assertion catches the bug by reintroducing it (checklist item 20).
      Done 2026-09-19: `test/domain/amp_state_test.dart` ("pending-command
      mask" group, incl. the unmasked counter-test) and
      `test/domain/amp_state_owner_test.dart` (socket → owner, rollback,
      400 ms fallback).

### 3.2.x — Power / boot state machine

- [x] **3.2.0** — States Off / Booting / On. Booting starts on a local power-on, ends on
      the amp's confirmation or a **20 s** timeout that silently falls
      back to Off; a late confirmation still corrects to On; repeated
      power-on taps don't extend the deadline. Power-off stays immediate.
      Done 2026-09-19: `BootInProgress` on `TrackedAmp` (its existence is
      the "self-initiated" flag), `togglePower`'s three branches,
      `docs/architecture.md` §9. **Power is sent for real** through
      `DevialetClientCommandSink` (owner decision). A late On after the
      timeout is plain On — no send, no hold. An on-tap while an optimistic
      Off is unconfirmed cancels the Off without a boot record (a stale On
      must not "confirm" a boot).
- [x] **3.2.1** — A "commands allowed" predicate derived from the machine (On and
      connected only), exposed so Task 3.5.1 can gate **every** entry point
      through the same function (checklist items 6, 28). Done 2026-09-19:
      `ControlViewState.commandsAllowed` / `powerCommandAllowed`; the owner's
      intents use them; `volumeGroupEnabled` / `powerEnabled` are aliases.
- [x] **3.2.2** — **Startup volume on a self-initiated power-on:** 500 ms after the
      confirming broadcast, send the configured startup volume
      (gotcha #9). ~~Not on an externally triggered power-on~~ (reversed
      2026-09-20 — see 3.2.5; checklist item 7). Done
      2026-09-19: `_runBootFollowUps` after every ingest/tick (effective
      +500…+700 ms, never earlier — no one-shot timers), sent once per
      booted amp even if the selection moved, **for real** via
      `sendStartupVolume`. Value: `kStartupVolumeDb = −40.0` clamped to the
      range (`AmpState.startupVolumeTarget`) until 3.4.8 supplies the setting.
- [x] **3.2.3** — **Post-boot display hold:** hold the shown volume at the target,
      record but don't apply incoming pushes, release on a *confirmed* value
      equal to the target or after 1500 ms. A user change inside the window
      re-targets both the hold and the deferred send. Done 2026-09-19: the
      hold *is* the pending mask armed at confirmation with a 1500 ms
      deadline (`resolvePending`); `setVolumeDb` inside the window keeps that
      deadline and re-targets `BootInProgress.target`. Proven with an
      `applyUnheld` counter-test (checklist 20).

- **S25 soak 2026-09-19 (owner):** the full boot loop works on the simulated
  amp — Off → Power → Booting (16 s) → On with the −40 hold while the sim
  misreports → corrected by the startup send. The real-amp capture (≥ 3
  boots) is Task 3.5.2.

- [x] **3.2.4** — **Bug (S25 soak 2026-09-20, owner): −42 flashes for a split
      second after a self-initiated boot before −40 shows.** Root cause,
      reproduced on the code: the first On packet carries the *pre-shutdown*
      byte, and when that equals the hold target (the owner's amp habitually
      sits at −40) `resolvePending` armed the hold and treated the same
      packet as its confirmation, releasing it before the −42 misreport
      arrived. The gotcha #8 test used −25 as the pre-shutdown byte and so
      never saw it. Fixed 2026-09-20 by porting the KDE widget's same-day
      fix: a matching byte releases the hold **only after the startup send
      went out**, and the 1500 ms fallback runs from the send (before it,
      from arming). Regression tests with pre-shutdown == target at the
      pure and owner levels; counter-run shows the flash back without the
      rule. `docs/known-gotchas.md` #8 "Watch out #2". Verified on the S25
      2026-09-20 (owner): an app-initiated boot settles on −40 at once.
- [x] **3.2.5** — **Observed (external) power-ons get the same follow-ups**
      (owner decision 2026-09-20, reversing 3.2.2's "not on an externally
      triggered power-on"): the owner rebooted the amp from the KDE widget
      and the app showed −42 until the *widget's* startup send re-synced
      the broadcast — by the old rule the app had no hold and sent nothing.
      Now an Off→On observed on the **selected** amp creates an
      already-confirmed boot record (`AmpState.ingest`): the hold arms at
      the target and the startup volume goes out at +500 ms; no Booting
      presentation (we did not start it). Consequences, recorded: after a
      remote / front-panel boot the app sets its startup volume, overriding
      one configured in the amp itself if they ever differ; two clients
      (widget + app) both send −40 — identical value, harmless, but if
      their startup settings differ the last sender wins. Non-selected amps
      get nothing. Counter-run: with the rule removed the external-boot
      tests show −42 and no send. Re-checked on the S25 2026-09-21 (Task
      3.5.2, trials D and E): two harness-initiated boots with the KDE
      daemon stopped — the phone held −40.0, sent the startup volume at
      +572 / +615 ms and the amp applied it by +800 ms.

### 3.3.x — Settings persistence layer

- [x] **3.3.0** — **Decision (recorded here so it isn't relitigated):** app
      preferences live in **app-local storage via the `shared_preferences`
      plugin** (`SharedPreferences` on Android, `UserDefaults` on iOS) —
      the same footprint the Kotlin app used for `amp_ip` / `amp_name`.
      Explicitly **not** Android `Settings.Panel` and **not** an iOS
      `Settings.bundle`: those are for OS-gatekept configuration
      (permissions, system toggles), not app preferences, and would split
      the settings across two UIs with two persistence paths. Done
      2026-09-20: `shared_preferences 2.5.5`, legacy `SharedPreferences`
      API (same Android footprint as the Kotlin app), confined to
      `lib/domain/settings/settings_store.dart`.
- [x] **3.3.1** — One typed settings object with named keys, defaults and validation
      in one place; controls are stateless and emit intents, the owner
      writes back (checklist item 9). Every value is stored on change and
      read back on open (checklist item 8). Done 2026-09-20: `AppSettings`
      + `SettingsNotifier` (`docs/architecture.md` §14). Consumed now
      (owner decision): the amp selection (3.9.1's persistence half), the
      volume limits and the startup volume; theme is stored with its
      default and consumed by 3.4.x.
- [x] **3.3.2** — Self-heal on load: an invalid stored pair or out-of-range value is
      repaired **before anything binds** (the specific rules are Task
      3.4.x's; the hook lives here). Done 2026-09-20: `hydrateSettings()`
      in `main()` before `runApp` — load, heal (3.4.7 ranges, 3.4.10 pair →
      −40/−39, step, theme, selection consistency), write repairs back; an
      unopenable store runs on defaults in memory and showed `PREFS OFF` in
      the debug bar (checklist 26; the bar went in 2.0.20 — Settings'
      persistence note is the surviving surface).
- [x] **3.3.3** — Testable against a disposable instance
      (`SharedPreferences.setMockInitialValues`, `ProviderContainer`
      overrides); nothing writes the real store from a test (checklist
      item 19). Done 2026-09-20: `InMemorySettingsStore` everywhere; the
      plugin is touched by exactly one adapter test. The simulated amp and
      test seeding go through owner-local seams that never persist —
      proven by a counter-test.
- [ ] **3.3.4** — Verify persistence through a **real app restart** (kill, not
      hot-reload) on the Galaxy S25 (checklist item 21). Script:
      1. pick the real amp in the sheet → `adb shell am force-stop
         com.ekmanch.devialet_expert_remote_app` (or swipe it away) →
         relaunch → it is connected without a tap once its first broadcast
         lands;
      2. choose "None" → force-stop → relaunch → the lone amp is **not**
         auto-selected;
      3. `adb shell pm clear …` (fresh install) → relaunch → the lone amp
         auto-selects;
      4. optional: `adb shell run-as … cat shared_prefs/FlutterSharedPreferences.xml`
         shows `flutter.selected_ip` / `flutter.has_explicit_selection`.
      A hot restart keeps the process's preferences and does not count.

## Task 3.4.x — Settings screen: UI + wiring to the persistence layer

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

- [x] **3.4.0** — Settings screen per variant (Material list on Android; grouped
      inset-style on iOS, native back behaviour), from the v19 mockup. Done
      2026-09-20: `lib/ui/settings/` — both variants use the mockup's
      grouped cards; the top bar is custom per variant (Android icon back
      + 22 px title, iOS "‹ Remote" + centred 16 px title); routes via
      `adaptivePageRoute` so system back / swipe-back come free.
- [x] **3.4.1** — **Navigation per width class:** compact = push from the header gear
      as in the mockup, and that is all this task builds. On the interim
      expanded column the same push is used. The two-pane variant
      (Settings beside Control) is Task 3.11.x's. Done 2026-09-20 —
      `SettingsBody` is separate from `SettingsScreen` so 3.11.x hosts it
      in a pane. ~~The draft/Apply flow, dirty-draft guard and Restore
      Defaults~~ are void: see 3.4.2.
- [x] **3.4.2** — ~~Draft → Apply/OK, not written from the click handler; "Restore
      Defaults" lives in the page and feeds normal dirty tracking.~~
      **Void by owner decision 2026-09-20: settings are effective
      immediately.** That is the Android/iOS platform convention (and the
      v19 mockup has no Apply, Cancel or dirty state); the KDE widget's
      draft → Apply/OK follows Plasma's config-dialog convention. The two
      deliberately differ on this point, each following its own platform.
      "Not written from the click handler" still holds in spirit: each
      control emits an intent and `SettingsNotifier` writes and persists
      (checklist 9). No Restore Defaults row for now (3.4.11).
- [x] **3.4.3** — Steppers: a tap moves exactly 1 dB; hold-to-repeat with
      acceleration; tap the value for direct numeric entry. The mockup's
      420 ms / 140→45 ms timings are a guess until measured (checklist
      item 14). Done 2026-09-20 (`DbStepper`, `StepperRepeatController`:
      step on press, first repeat at 420 + 140 = 560 ms as the mockup's
      `setInterval`, then −12 ms per tick to 45 ms; tap-to-type is
      magnitude-only with the minus supplied, clamped, empty/Escape
      revert). **Timings still unmeasured** — record the S25 feel here.
- [x] **3.4.4** — The blocked stepper (floor/ceiling at the 1 dB gap) dims to 0.4 and
      refuses — no silent no-op, no flash. Done 2026-09-20: only the
      blocked ± button dims (KDE), also at −96 / 0; counter-run: without the
      bound the same tap moves the value.
- [x] **3.4.5** — Settings list for v1: floor, ceiling, startup volume, step size.
      **Decisions 2026-09-20 (owner):** Theme (system/dark/light) and About
      (Version, View on GitHub) rows **included** as the mockup shows; the
      selected-amp / manual-IP row **excluded** — the amp card on the
      Control screen owns selection and a second entry point would only
      confuse (manual IP stays in the amp sheet). Theme is consumed in
      `app.dart::wrap`; Version is `kAppVersion` (pinned to `pubspec.yaml`
      by a test); GitHub opens through `url_launcher`.
- [ ] **3.4.6** — A setting that reflects external state (notification permission,
      local-network permission, background refresh) stores no bool: query
      on open, apply on Apply, re-query after every write, derive the
      control from the answer; if it can't be toggled, disable it and say
      why in a visible note (checklist item 26). *(None exist yet; the iOS
      local-network permission arrives with Task 4.0.0.)*

### Values and rules (wired to Task 3.3.x)

- [ ] **3.4.7** — Three persisted dB values over −96..0: floor **−50.0**, ceiling
      **−10.0**, startup **−40.0** Change `VolumeCodec.defaultSafetyMaxDb`, the UI
      range and the −15 pinning test **together, once**, reading from the settings
      object (gotcha #6, checklist item 28; the required-parameter part is Task 1.1.3).
      Done 2026-09-20 with 1.1.3: `VolumeCodec.defaultSafetyMaxDb` is gone,
      `encodeCommandWord` / `setVolume` / `setVolumeDb` / `selectSource`
      take a **required** `maxDb` (`null` = explicitly unbounded),
      `DevialetClientCommandSink` reads the settings ceiling at send time,
      the −15 pinning test became "null passes through, −10 clamps" plus a
      pin on `AppSettings.defaults.ceilingDb == −10`.
- [x] **3.4.8** — Ceiling enforced inside the command constructor as a required
      parameter with explicit "none"; floor is UI-only and never reaches
      the wire. Done 2026-09-20 (see 3.4.7). `DevialetClient.sourceSwitchVolumeDb`
      stays a constant until 3.8.1 swaps it for the startup setting.
- [x] **3.4.9** — Step size setting: 0.5 / 1 / 2 dB, default **1.0**. Done
      2026-09-20 (segmented control → `setStepDb`; consumed by 3.6.0).
- [x] **3.4.10** — Floor and ceiling mutually constrained at the point of interaction,
      **1 dB minimum gap**. Self-heal an invalid stored pair on load to
      floor −40 / ceiling −39 before anything binds. Done 2026-09-20: by
      bounds as KDE (`floor.max = ceiling − 1`, `ceiling.min = floor + 1`;
      only the pressed value moves); the heal has been in 3.3.2 since 3.3.x.
- [ ] **3.4.11** — "Restore Defaults" writes in constraint-safe order (**widen first**)
      so every intermediate state is valid (checklist item 10). *(Deferred
      by owner decision 2026-09-20 — no row for now; the owner-side
      `restoreDefaults()` with widen-first ordering exists and is tested.)*
- [x] **3.4.12** — Every control persists and is verified after a real restart
      (checklist items 8, 21). Also surface `SettingsNotifier.lastWriteError`
      and `HydratedSettings.storeUnavailable` in the screen (checklist 26).
      Done 2026-09-20; **S25 soak (owner, 2026-09-20):** settings persist
      across app sessions, light theme works, tap-to-type works, View on
      GitHub opens the repo. Not yet reported: the stepper hold feel
      (3.4.3 timings stay unmeasured) and the amp-selection restart
      scenarios of 3.3.4.
- [x] **3.4.13** — The clamp that a limit change applies *to the amp* is Task 3.6.6's
      (it needs the pending mask and the power/boot re-trigger); this task
      only stores and validates. Done 2026-09-22 with 3.6.6.

## Task 3.5.x — Power / boot wiring (depends on 3.2.x)

- [x] **3.5.0** — Power button → owner → `powerOn` / `powerOff`; Booting presentation
      from Task 2.0.0 driven by the machine; Booting is entered only on a
      self-initiated power-on. *(Already true since 3.2.0 — the button calls
      `togglePower`, which sends for real.)* Done 2026-09-21: UI pass
      through six real boots on the S25 (screenshots, Android variant) —
      Off = hollow dot / "Power On" / everything else dimmed with the
      last value kept; Booting = spinner + "Powering on…" + "Booting…" +
      pulsing dot for the whole ~16 s, a repeat tap sends nothing; first
      On = "Power Off", copper dot, all groups un-dim in one frame, dial
      −40.0 at once; an external boot shows plain Off, never Booting.
      Report: `docs/protocol-verification-2026-09-21-boot.md`.
- [x] **3.5.1** — Every control except power is disabled while Off or Booting (the amp
      drops commands in those states); power is live while Off, disabled
      while Booting. **Enumerate every entry point** (buttons, dial drag,
      mute, source sheet, amp sheet, any hardware-key passthrough) and
      route each through the one predicate (checklist item 6). Done
      2026-09-21; the enumeration lives as a table above
      `ControlViewState.commandsAllowed`. Audit result: dial, mute, power
      and the source trigger were already gated at the widget **and** the
      owner; two gaps closed — **VOL −/+ had no `enabled` of their own**
      (only the ancestor `DimmedGroup`; `VolumeButtons.enabled` now, with
      `test/ui/volume_buttons_test.dart` proving the flag alone stops the
      callback and its `enabled: true` counter-half proving the tap
      otherwise lands) and **source-sheet rows stayed live if the amp
      went Off / Booting under an open sheet** (owner decision 2026-09-21:
      rows dim to 0.4 and go inert in place, sheet stays open — 3.8.2's
      auto-close is untouched; `sheets_test.dart` flips the state under
      the open sheet and its counter-half shows the same tap popping the
      sheet once the gate re-opens, which the owner-only gate would never
      have prevented). Recorded as *not* gates: amp-sheet rows / None /
      manual IP (selection is not an amp command), the device card and
      the gear; no hardware-key, `Shortcuts`, `Actions` or semantics
      action path exists; the debug bar drives `ingest`, not intents.
      Counter-run: with both new widget gates removed, 12 tests go red.
      Verified live on the S25 with the sheet open across a harness
      power cycle (report, trial E).
- [x] **3.5.2** — Startup-volume send and post-boot display hold observed end-to-end
      on the real amp: raw UDP capture next to the app, ≥ 3 boots, report
      recorded here (checklist item 22). Done 2026-09-21 —
      `docs/protocol-verification-2026-09-21-boot.md`, captures in
      `docs/captures/2026-09-21-boot-verification{,-app}.txt`. Six boots
      (one control with the app stopped: raw 111 persisted 30 s, nothing
      corrected it; three app-initiated; two external with the app
      watching; the KDE daemon stopped for the run). On all five
      app-observed boots the display went to −40.0 on the first On packet
      and never showed −42; the startup send went out at +555…+615 ms
      and the amp applied it by the +800 ms broadcast (5/5); every hold
      released on the real confirmation at +776…+822 ms, the 1500 ms
      fallback never fired; the 3.2.4 case (powered off at −40) held
      correctly on hardware. Boot time 15.0 s ×3 (harness power-on) /
      16.0–16.1 s ×3 (app power-on). Tooling added for it and for every
      later live check: a `kDebugMode`-only `[amp]` trace over logcat
      (`lib/domain/amp_trace.dart`, `docs/architecture.md` §15) and
      `tool/protocol_probe/run5_boot.py`. Hands-free over wireless adb.
- [x] **3.5.3** — **Bug (owner, 2026-09-22): the booting dot on the amp card pulsed
      at half the KDE widget's speed.** The mockup declares `dotPulse 1.1s`
      for the *whole* cycle (1 → 0.35 → 1) and the widget animates 550 ms
      down + 550 ms up; `DeviceDot` used 1100 ms as the controller
      duration with `repeat(reverse: true)`, i.e. a 2.2 s cycle (checklist
      15: the declared number described the cycle, the port used it as a
      leg). Fixed 2026-09-22: `kDotPulseLeg = 550 ms`;
      `test/ui/device_dot_pulse_test.dart` samples 0.35 at 550 ms and 1.0
      at 1100 ms (counter-run with 1100 ms: both fail).

## Task 3.6.x — Volume wiring: buttons + dial (depends on 3.1.x, 3.4.x)

Wired 2026-09-22 (owner decisions that day: the dial sends **only on
release**, as the KDE widget's slider — paced sends during a drag are
3.6.8; mute is flipped real in the same pass, 3.7.x). The sink's
`setVolumeDb` / `setMute` are real; `selectSource` stays a stub (3.8).
Trace events `send volume`, `send mute`, `clamp` (`docs/architecture.md`
§15).

- [x] **3.6.0** — One discrete input (tap, hardware key if ever mapped) = exactly one
      step of the configured size; the dial snaps to the same step. Done
      2026-09-22: `AmpState.stepDb` mirrors the setting like the range and
      reaches the dial through `ControlViewState.stepDb` (a *required*
      dial parameter — checklist 2); `AmpStateOwner.stepVolume` reads it.
      A screen reader's activate action on VOL ± steps once too (the
      press-to-step path would otherwise have made it a dead entry point,
      checklist 6). Accepted divergence: the dial's grid is anchored at
      0 dB (`quantizeDb`), the buttons step from the current value; they
      only differ for an odd floor with a 2 dB step (−51 → the buttons
      reach −49, the dial cannot).
- [x] **3.6.1** — Hold-to-repeat: 300 ms initial delay, 100 ms interval, flat.
      ~~(measured, not the mockup's 400/100)~~ **Correction 2026-09-22:
      these are not measured anywhere** — the KDE widget's `autoRepeat`
      values were copied from the Kotlin app (its commit `bc97159` says
      so), and no repo holds a measurement (checklist 14/29). Kept for
      widget parity. Done 2026-09-22: `StepperRepeatController` generalised
      (`firstRepeatAt` / `interval` / `accel` — the settings stepper keeps
      its 560 ms / accelerating schedule), `VolumeButtons` steps on
      press-down through `AdaptivePressable.onPressedChanged`, stops on
      release / cancel / a bound (`stepVolume` returns false) / disable
      mid-hold (`AdaptivePressable.didUpdateWidget` releases the press for
      every user of the widget). Known and recorded, not fixed: inside the
      `SingleChildScrollView` the tap arena delays the press by
      `kPressTimeout` (100 ms), so the first repeat lands ≈ 400 ms after
      the touch and a quick tap steps at pointer-up. Measured on the S25
      2026-09-22 (3.6.7): first repeat +303 / +308 ms after the press
      step, then 102–104 ms; the arena delay itself is not visible in the
      logs (different clocks) — **owner: record the feel here** before
      deciding whether to subtract it.
- [x] **3.6.2** — Every step path computes `clamp(base + dir·step)` on the
      already-clamped synchronous value; clamp is idempotent. Done
      2026-09-22: `AmpState.clampDb` is the one clamp (min/max);
      `stepVolume` (buttons), `setVolumeDb` (dial) and the limit clamp all
      write through one private `_writeVolume`; a bound step returns false
      and sends nothing (a bound press on a *muted* amp still unmutes and
      re-asserts, as KDE sends there).
- [x] **3.6.3** — One fraction value feeds every meter (dial arc, any indicator bar);
      never computed three times. Done by construction: `dialFraction()`
      (`volume_dial_math.dart`) is the single function; the arc is the
      only meter today — 3.10.x's toast must call it, not re-derive.
- [x] **3.6.4** — Exception, by design: an actively dragged dial displays its own
      local position, not the round-tripped value; block scroll/wheel-style
      deltas entirely while a drag is in progress. Done 2026-09-22: the
      drag value lives in `ControlScreen._dragDb` (gesture state, not a
      copy) and the readout follows it even on a muted amp (KDE's label is
      bound to the slider). Gap closed: the group going inert mid-drag
      (Off / silent under the finger) now drops the drag uncommitted —
      the dial's callbacks are nulled while disabled so its release never
      arrived and the readout stayed stuck. **Wheel: N/A** — no
      pointer-signal path exists in `lib/`; whoever adds one (tablet
      trackpad, mouse) must ignore it while `VolumeDialState._lastDb !=
      null`, as KDE's `onWheel` returns while `pressed`.
- [x] **3.6.4b** — When user volume sends land here, a user re-target inside the
      post-boot hold must count as the hold's "send" (KDE `notifyVolume`
      sets `bootHoldSent`): flip `BootInProgress.startupSent` and restart
      the fallback from that send, so the user's value can confirm the
      hold. Done 2026-09-22 with a separate flag, `BootInProgress.userSent`
      (`holdConfirmable = startupSent || userSent`), the fallback restarted
      from the user's send. **Deliberate deviation from the widget:** the
      deferred +500 ms startup send still goes out, carrying the
      re-targeted user value, even when the user's own confirmation already
      released the hold — the widget sends the *configured default* there
      (its `bootHoldIp` is cleared on release). A user send at +50…+394 ms
      can be silently dropped (gotcha #9), and the deferred send is the
      only recovery; it must never override the user. Also: the startup
      send is clamped to the limits *in force at the send* (a Settings
      change during a 16 s boot), so the post-boot limit clamp is a no-op.
- [x] **3.6.5** — Auto-unmute on a *user* volume change (±, dial) — a client decision;
      the wire does not unmute (`docs/protocol.md`, "Volume and mute are
      independent"). Done 2026-09-22: `mute off` **then** the volume (KDE
      order), two sends with separate rollbacks so a failed unmute never
      rolls the volume back; the optimistic `pendingMuted(false)` makes a
      10-tick hold send exactly one mute-off; once the 400 ms mask expires
      with the amp still muted the next gesture re-sends it (the gesture
      retries the dropped command — desired). Corrections (startup send,
      limit clamp) never unmute (3.7.1, counter-tested).
- [x] **3.6.6** — **Limit-change clamp:** immediate clamp when floor/ceiling change,
      both directions, scoped to the connected amp, amp stays muted through
      it, one Apply changing both values coalesced into exactly one
      command, nothing sent when already in range; re-run on connection
      landing and on power reaching On (checklist item 11). Done
      2026-09-22, port of KDE `applyImmediateClamp`: `_applyLimitClamp`
      runs in one coalescing microtask (`_scheduleLimitClamp`) triggered by
      the settings listener (floor/ceiling changed) and by the owner's
      `_afterWrite` hook — which runs after **every** state write (ingest,
      tick, `_arm` incl. rollbacks, selection, seams) and fires on an
      eligibility edge (`selected && online && On && boot == null`
      false→true, or the selected ip changing while eligible). "Power
      reaching On" is therefore "the boot record dropped" — by then the
      amp sits at the clamped startup target, so a send inside gotcha #9's
      window is never raced. One evaluation per trigger, no timer retry
      (KDE parity). Phone note: settings are effective immediately, so
      "one Apply" here means one synchronous run (`restoreDefaults`,
      two seam writes) — proven to produce one command.
- [x] **3.6.7** — Verified against gotchas #1/#2 by hand on the Galaxy S25 (release
      the button / the dial mid-broadcast) with a raw capture next to the
      app; report recorded (checklist items 22, 23). Done 2026-09-22 (the
      scripted half): `docs/protocol-verification-2026-09-22-volume.md`,
      captures in `docs/captures/2026-09-22-volume-verification{,-app}.txt`,
      `tool/protocol_probe/run6_volume.py` (listener + restore; envelope
      in its header). Taps, two holds (17 and 7 sends at 300/100), three
      dial releases, mute → step / drag → unmute, seven floor-driven
      clamps (one command per excluding change, none in range, muted
      stays muted) and a None-selected control tap — every `view` line
      moved with the gesture, no jerk after any release; confirmations
      81…288 ms. **Owner hands-on still to record here** (checklist 23):
      the 300/100 feel incl. the ≈100 ms arena delay (3.6.1), dial
      tracking on release, the muted → drag → unmute path.
- [ ] **3.6.8** — *(deferred, owner decision 2026-09-22)* Paced sends **during** a
      dial drag (at most one every 100 ms, like the button repeat, plus the
      release value) so the amp follows the finger like the physical knob.
      Release-only is the widget's behaviour and shipped first; revisit
      after the 3.6.7 soak if live tracking is missed.

## Task 3.7.x — Mute wiring (independent; do early if convenient)

Done 2026-09-22 together with 3.6.5 (owner decision: auto-unmute needs the
real mute send).

- [x] **3.7.0** — Mute is its own opcode, independent of volume; the owner exposes it
      through the same pending mask as everything else. Done 2026-09-22:
      `DevialetClientCommandSink.setMute` is real (`send mute` trace);
      `toggleMute` was already masked through `pendingMuted`.
- [x] **3.7.1** — Corrections sent while muted (limit clamps, startup volume) leave the
      amp muted; only Task 3.6.5's auto-unmute on a *user* volume change
      unmutes. Done 2026-09-22: `_writeVolume(userIntent: false)` cannot
      touch the mute slot; counter-tested (startup send and clamp on a
      muted amp: no mute call, view stays muted).
- [x] **3.7.2** — Numeric readouts derive "Muted" from confirmed+masked state, not from
      the button's own toggle (checklist item 9). Already true since 3.0.x
      (`ControlViewState.isMuted` ← `displayedMuted`); during a dial drag
      the finger's value wins over "Muted" (3.6.4).

## Task 3.8.x — Source selection wiring

- [ ] **3.8.0** — Names come from the live broadcast only; always 30 slots, `selected`
      derived per slot, filtered to enabled for display; bounds-check the
      chosen index where the model lives. Never hardcode a per-unit name
      for an index (`docs/protocol.md`, "Names are per-unit").
- [ ] **3.8.1** — **Every switch sends the forced startup volume** (Task 3.4.7's value,
      source×2 then volume×2, zero delay) — so **never bind a casual
      gesture (scroll, swipe) to cycling sources**.
- [ ] **3.8.2** — Amp sheet and source sheet mutually exclusive by code; both reset to
      closed when the screen is left or when power leaves On.
- [ ] **3.8.3** — Diff keys include selection state, not just names (gotcha #4).

## Task 3.9.x — Amp discovery / selection list wiring

- [ ] **3.9.0** — Discovery map keyed by sender IP, updated by every broadcast, never
      evicted; silent amps flip to offline after 8 s; the sheet's list
      refreshes live while open. *(Map, eviction rule and staleness exist
      since 3.0.x; remaining: the sheet watches the live list, and the
      offline-row presentation vs. hidden — 3.0.8 chose hidden.)*
- [x] **3.9.1** — Persist selection with **two distinct states**: "chosen X" and
      "chosen nothing (None)", plus a "user has chosen" flag, so restart
      never resurrects a default the user opted out of (checklist item 4).
      Done 2026-09-20 in Task 3.3.x (`selected_ip` + `has_explicit_selection`,
      restored in `AmpStateOwner.build()`; the S25 restart check is 3.3.4).
- [ ] **3.9.2** — Auto-select-if-alone: nothing selected, never chosen, exactly one amp
      known → that amp; 0 or 2+ → not-connected, don't guess.
- [ ] **3.9.3** — Manual-IP fallback: a never-heard IP is a valid selection; no
      reconciliation step, staleness governs connectedness.
- [ ] **3.9.4** — Not-connected state: name `""`, offline, sources `[]`, power Off, and
      **no volume reading** — check "is there an amp" before any clamp so a
      zero default can't display as "−15.0 dB" (checklist item 5).
- [ ] **3.9.5** — mDNS model name: `_spotify-connect._tcp.local.`, trusted only for an
      IP already heard over UDP, resolved once, carried across
      re-ingestion; `parseModelName` per `docs/protocol.md` with its three
      test cases. Platform-native browse per OS (no `NsdManager` restart
      bursts); iOS needs `NSBonjourServices` + local-network permission
      (see Task 4.0.0).

## Task 3.10.x — Transient feedback (lower priority; can trail the above)

- [ ] **3.10.0** — A local-interaction cue (fires only from your own gesture) with
      reset-and-replace semantics: each new value cancels the pending
      dismiss, snaps content, restarts a fixed **1800 ms** timeout; no
      queueing. Icon tiers: muted or ≤0 % → mute, ≤25 % low, ≤75 % medium,
      else high. Content derives from confirmed state (checklist item 25).
- [ ] **3.10.1** — Any passive mirror (home-screen widget, notification, watch
      complication — if ever built) reflects shared state including
      remote-originated changes; the transient cue does not.
- [ ] **3.10.2** — Don't reuse the OS's own volume OSD look; users mistake it for the
      device's volume. No mockup exists for this cue yet — sketch it in the
      current mockup HTML (v40 today; bump it) before building.

## Task 3.11.x — Expanded-width two-pane layout (tablets; after 2.0.x and 3.4.x)

**Owner decision 2026-09-19:** expanded widths get a **two-pane layout**
(it will look nicer on a tablet than a centred phone column). Deferred to
here, after the Control and Settings screens exist and are wired, because
the owner's only tablet is an iPad and loading the app onto it is a whole
process that shouldn't gate early tasks. Everything in this task is
previewed on an **Android tablet emulator or a resizable desktop window**
via both UI variants; the real-iPad check is Task 4.4.0.

- [ ] **3.11.0** — **Tablet mockup pass** in the current mockup HTML (v40 today, both variants) before any
      code: which pane pairs are shown at expanded width (Control +
      Settings; Control + amp/source lists), what medium width does
      (probably still single-pane, wider column), pane proportions, where
      the header/amp card lives, and how sheets become popovers / form
      sheets / side panels per platform (mockups-before-code; checklist
      items 14, 15 — measure the mockup, don't trust its declared numbers).
- [ ] **3.11.1** — Build the two-pane layout on Task 2.0.0's width-class plumbing,
      replacing the interim centred column; compact stays the mockup
      layout untouched.
- [ ] **3.11.2** — Settings in the side pane: same draft/Apply component as Task
      3.4.x, no second copy of the draft; Apply is reflected on the
      Control pane that never left the screen (Task 3.0.6's "no one
      screen at a time" rule; checklist items 2, 11).
- [ ] **3.11.3** — Width-class transitions while connected (rotate, resize) keep the
      open sheet / drag / draft (Task 2.0.0's runtime-resize item),
      re-checked with two panes.
- [ ] **3.11.4** — Hands-on check on the emulator / desktop window recorded here; the
      iPad soak stays in Task 4.4.0 / 5.0.1.

## Task 4.0.x onward — iOS-specific (after 2.x/3.x are proven on Android)

- [ ] **4.0.0** Local-network permission flow
      (`NSLocalNetworkUsageDescription`, `NSBonjourServices`), incl.
      "denied" and "not yet asked" states, surfaced as an external-state
      setting per Task 3.4.x (checklist items 17, 26).
- [ ] **4.1.0** Backgrounding: expect status loss within seconds; design
      the resume path (re-bind, staleness re-evaluation, pending mask and
      boot machine reset) rather than assuming parity (checklist item 30).
- [ ] **4.2.0** ATS / `NSAllowsLocalNetworking` for plaintext UDP.
- [ ] **4.3.0** iOS UI pass on a physical device: everything Task 2.0.0
      previewed through the `ios` UI variant on the Galaxy S25, re-checked
      on real iOS (fonts, safe areas, back behaviour, sheet dismissal).
- [ ] **4.4.0** iPad pass on the owner's iPad — the **first** time the app
      is loaded onto it, by design (Task 3.11.x): every width class via
      Split View, Slide Over and Stage Manager resizing while connected
      (state survives, sockets don't); all four orientations already
      declared in `Info.plist`; decide and record whether
      `UIRequiresFullScreen` stays off (it must, for multitasking);
      sheets become popovers/form sheets per iPadOS convention;
      local-network permission (4.0.0) and backgrounding (4.1.0)
      re-checked on iPadOS, which suspends a Slide Over window on its own
      schedule. App Store iPad screenshots are part of the deliverable.

## Task 5.0.x — Polish

- [ ] **5.0.0** — **Custom app icon.** Copper/graphite visual language, replacing stock
      Flutter/Android/iOS default icons. The KDE widget shipped a copper
      glow-dot panel icon and a brand tile picker icon in that language
      (`icons/hicolor/scalable/apps/`, `plasmoid/contents/icons/` in that
      repo) — reuse the assets/tokens if the brand should match. Concept
      directions explored previously: Dial Arc, Signal Dot, Waveform Bars,
      Faceplate, Concentric Rings.
- [ ] **5.0.1** — Human soak on the Galaxy S25 **and the iPad** with the gesture-only
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

- [x] Once the tcpdump items above are resolved, update `docs/protocol.md`
      to flip their status from "inferred, not confirmed" to confirmed (or
      correct them if the capture reveals different behavior than assumed).
      Done 2026-09-19 (✔ marks; broadcast rate corrected from "~1 Hz" to a
      steady 5 Hz; counters, CRC, padding, select encoding, volume word as
      `bfloat16`, latency 82–200 ms; gotcha #3 guidance updated).
- [ ] `docs/protocol.md` and `docs/known-gotchas.md` still point into this
      file with the old wording ("state owner / pending-command mask
      phases"). Retarget those pointers to Task 3.0.x-3.1.x on the next
      docs touch. ("Phase 1 follow-ups" and "volume-limits phase" were
      retargeted to Task 1.1.x / 3.4.x on 2026-09-19; the floor default
      in both docs was corrected to −50.0 to match 3.4.7.)
