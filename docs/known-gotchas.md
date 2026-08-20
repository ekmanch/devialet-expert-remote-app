# Known Gotchas — Bug History

Every commit in this repo's history (26 total) that fixed a real bug, safety
issue, or UX-breaking race condition, found via `git log --oneline` +
`git show` on each candidate. Based on `main` @ `743aa71`. No automated tests
exist in this repo, so all of these were presumably caught by hand-testing
against a physical amp.

## 1. Volume jump/jerk after releasing VOL +/- buttons — [Control]

- **Symptom:** amp would report a different volume than the one the user
  actually stopped at when releasing the VOL - / VOL + button; the on-screen
  value visibly jumped/jerked right as the button was released.
- **Root cause:** the amp's own status broadcast (~1x/sec) can land *while* a
  volume change is in flight, still reporting the pre-change volume. The app
  was applying every incoming status broadcast unconditionally, so a
  stale/in-flight broadcast would momentarily overwrite the just-set value.
- **Fix:** added a debounce window (`volumeButtonDebounceMs`, repeat interval
  + 300ms buffer) after each button-driven volume step; incoming status
  broadcasts are ignored for that window so a stale broadcast can't stomp the
  just-sent value.
- **Commit:** `c80e329`
- **Watch out for this in Flutter:** any "optimistic local update, then
  reconcile against periodic device state" pattern needs a debounce/ignore
  window keyed off *when the local change was made*, not just a "user is
  actively dragging" flag — the race is between "I just sent X" and "I'm
  about to receive a broadcast describing pre-X state," which can happen even
  after the user has let go.

## 2. Same race, but for the volume dial/slider release (not the buttons) — [Control]

- **Symptom:** identical jump/jerk, but triggered by releasing the volume
  slider/dial drag rather than the step buttons.
- **Root cause:** identical race to #1 — releasing the slider sends the new
  volume, but an in-flight broadcast reporting the pre-release volume can
  land right after and snap the UI back before the *next* (correct) broadcast
  snaps it forward again.
- **Fix:** added a second debounce timestamp (`lastVolumeSliderReleaseAtMs`),
  reusing the same debounce window/constant as the button fix (#1) since it's
  the same underlying round-trip.
- **Commit:** `9f013b6`
- **Watch out for this in Flutter:** don't assume fixing this race for one
  input widget (buttons) also covers another (a drag gesture) — this codebase
  needed the same fix applied twice, once per input method. Any new
  volume-setting UI element (e.g. a second slider style, a hardware volume
  key passthrough) will need the same debounce treatment.

## 3. Wrong source selected — Optical 1 selection played Roon Ready instead — [Control]

- **Symptom:** selecting a source (e.g. tapping "Optical 1" in the UI) caused
  the amp to actually switch to a *different* source (e.g. "Roon Ready").
- **Root cause:** the command byte value for source selection was assumed to
  equal the source's index from the status broadcast (0–14), but the two are
  not the same — the amp's select-source command expects a different,
  non-linear value per source. The original code passed the raw status index
  straight through.
- **Fix:** introduced an explicit `SOURCE_COMMAND_VALUE` lookup table mapping
  status-broadcast index → command value for the known sources, with Phono
  handled as a separate hardcoded-byte special case (see below). Unmapped
  indices still fall back to passing the raw index through (unverified for
  those).
- **Commit:** `3aecc1a`
- **Watch out for this in Flutter:** **do not** assume the status-broadcast
  source index can be reused directly as the command value when
  reimplementing source selection — this table (and the Phono special case)
  must be ported byte-for-byte, not "cleaned up" or re-derived from a formula,
  since the underlying mapping is non-linear and only known empirically.

## 4. ACTIVE source in the UI didn't update after the user changed it — [Control]

- **Symptom:** after selecting a new source from the app, the UI kept showing
  the *previous* source as active until (presumably) the next broadcast
  eventually caught up, if it caught up correctly at all given bug #3 was in
  the same commit.
- **Root cause:** bundled into the same commit as #3 (this repo doesn't split
  logically-related fixes into separate commits) — the source-row rebuild
  logic in the UI only diffed on the *set of available source names*, not on
  which one was currently selected, so a pure selection change (no change to
  the list of sources) never triggered a re-render of which row shows as
  active.
- **Fix:** the rebuild "dirty" check was changed to key off `(name, isSelected)`
  pairs for every source, not names alone, so a selection-only change is
  correctly detected as needing a redraw. (Present in current code as the
  `tagKey` comparison in `MainActivity.rebuildSourceList()`; the code comment
  there explicitly explains the old bug: "Comparing names alone meant this
  always short-circuited after the first draw.")
- **Commit:** `3aecc1a`
- **Watch out for this in Flutter:** when diffing "should I rebuild this list"
  against incoming device state, make sure the diff key includes *selection
  state*, not just item identity/labels — a naive `list.map(name) == cached`
  check will miss selection-only changes exactly like this did.

## 5. Amplifier picked an inconsistent volume after switching sources — [Control]

- **Symptom:** switching inputs from the app left the amp at whatever volume
  it happened to remember for that input — inconsistent across sources
  (observed -40dB on Optical 1 vs -38dB on others), which read as broken/random
  behavior to the user even though it was actually just the amp's own
  per-input volume memory.
- **Root cause:** not a bug in this app's protocol handling per se — a
  quirk of the amp's own firmware behavior that the app hadn't compensated
  for.
- **Fix:** after every source switch, the app now unconditionally also sends
  a fixed `setVolumeDb(-40.0)` command, overriding whatever the amp would
  otherwise pick.
- **Commit:** `88d97eb`
- **Watch out for this in Flutter:** this is a deliberate **product decision
  masking a hardware quirk**, not a protocol requirement — must be explicitly
  carried over (source-select → forced volume, every time, no source
  exceptions) or the Flutter version will regress to the "random volume on
  input switch" complaint. Don't optimize this away as a redundant network
  call.

## 6. Dangerously loud volume reachable from the app (0dB was too loud) — [Control]

- **Symptom / risk:** the app allowed requesting up to 0dB, which was
  "dangerously loud" on the Expert Pro 140 — a real safety/hardware-damage and
  hearing-safety concern, not just a UX nit.
- **Root cause:** `setVolumeDb`'s safety clamp (`maxDb`) defaulted to `0.0`,
  and the UI's slider range matched it (0..60 steps mapping to -60..0 dB).
  The Devialet protocol itself supports up to +30dB — nothing at the protocol
  layer stops you from asking for a dangerous level.
- **Fix:** lowered the default safety clamp to **-15.0 dB** and correspondingly
  shrank the UI slider's range/labels to match, so the UI can't even present
  the option of going louder.
- **Commit:** `c6e2b63`
- **Watch out for this in Flutter:** **-15dB is a deliberate safety ceiling,
  not an arbitrary default** — carry it over exactly, at both layers (the
  network-layer clamp *and* the UI range), not just one. Don't "restore" the
  full -60..0 (or wider) range while porting UI polish without re-confirming
  the safety rationale with the user first. This is exactly the kind of thing
  that's easy to silently regress during a rewrite because it looks like a
  leftover/arbitrary constant.

## 7. Lint: touch-handling didn't call `performClick()`, breaking accessibility semantics — [Control]

- **Symptom:** Android Studio's Code Analysis lint flagged the VOL +/- button
  touch handling for not calling `performClick()`, which is the accessibility
  hook screen readers etc. rely on for custom touch handling.
- **Root cause:** volume repeat used a raw `setOnTouchListener` for
  press-and-hold behavior (added in `af9b927`, see the codebase's press-and-hold
  feature history) without also explicitly invoking `performClick()` on the
  matching `ACTION_UP`, since the touch listener fully replaced normal click
  handling.
- **Fix:** explicitly call `v.performClick()` on `ACTION_UP` from within the
  touch listener itself.
- **Commit:** `7990cf0`
- **Watch out for this in Flutter:** not directly portable (Flutter's gesture
  and semantics systems work differently from Android's `View.performClick()`
  contract) but the underlying lesson carries over — any custom
  press-and-hold/drag gesture implementation needs its own explicit
  accessibility semantics (Flutter's `Semantics`/`GestureDetector.onTap` etc.),
  since a fully custom low-level gesture handler bypasses the framework's
  default accessibility wiring the same way a raw `OnTouchListener` did here.

## Non-bugs worth knowing about (deliberate behavior, not defects)

- **No retry beyond a fixed double-send** (`sendTwice`) has existed since the
  initial commit and was never revisited as a "bug" — commands are just sent
  twice, no ack, no adaptive retry. Not a fix, but also not obviously robust;
  flagging in case the LAN conditions during Flutter development differ
  (e.g. Wi-Fi vs. the Ethernet-oriented use case implied by `usesCleartextTraffic`
  and general Devialet Ethernet-first design). **[Shared]** — applies to every
  command family, not just Control.
- **SAM / Night Mode / SAM level / Bass / Treble are permanently unimplemented**
  at the protocol layer as of `743aa71` — this isn't a regression to fix, it's
  a known gap (see `docs/protocol.md`, "Known-unimplemented commands"). Don't
  mistake the local-only UI toggles for working controls when testing the
  Flutter port against the current feature set. **[Sound]**
