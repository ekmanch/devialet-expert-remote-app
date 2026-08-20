# TODO

Running list of deferred work for `devialet-expert-remote-app`. Update this
alongside code changes rather than letting it drift — treat it as the source
of truth (not chat history / memory).

## Protocol verification (tcpdump workstream)

- [ ] **Confirm counter-caveat behavior via tcpdump.** Phase 1 replicated the
      Kotlin app's apparent double-increment of both counters on every packet
      (see `docs/known-gotchas.md`), without confirming via packet capture
      whether this is intentional protocol behavior or an unfixed bug being
      carried forward. Capture real traffic and diff against the current
      implementation to confirm or correct.
- [ ] **Confirm fallback-to-raw-index behavior for unmapped sources.**
      `docs/protocol.md` flags this as inferred, not confirmed. Needs a real
      amp with an unmapped/unusual source (or deliberately triggering the
      fallback) plus a packet capture to verify.
- [ ] **Fresh tcpdump captures toggling Night Mode, SAM level, bass, and
      treble** from the Devialet phone app, diffed against the baseline
      598-byte heartbeat, to check for byte-level changes in the UDP
      broadcast. (SAM on/off already confirmed to produce no change in this
      packet — see `docs/known-gotchas.md` / prior session notes. Night Mode,
      SAM level, bass, and treble remain untested. Bass/treble are
      highest-probability targets given their continuous numeric values.)
      This is prerequisite work for any future Sound-tab implementation.

## Build / tooling

- [ ] **AGP declarative DSL migration** (only relevant if/when native Android
      build tooling is touched directly — most of this is now Flutter, but
      flag if still applicable). Non-urgent, still supported through AGP 9.x.
- [ ] **`targetSdk` bump (34 → 37)** — once bumped to Android 17, raw UDP
      socket usage will require the new `ACCESS_LOCAL_NETWORK` runtime
      permission. Handle both together, not separately.

## UX / feature work (post scaffold)

- [ ] **Power-on "Booting up…" state.** After tapping "Power On," show a
      distinct loading/progress state until the amp reports on. Add a
      ~10–15s timeout reverting to "Power On" with a red tint if the amp
      fails to boot.
- [ ] **"Not responding" state.** When the selected amp is unreachable, apply
      the same greyed-out/disabled treatment as the no-amp-selected state
      (currently would show stale active-looking UI with only a small
      subtitle indicating the issue).
- [ ] **Custom app icon.** Copper/graphite visual language, replacing stock
      Flutter/Android/iOS default icons. Concept directions explored
      previously: Dial Arc, Signal Dot, Waveform Bars, Faceplate, Concentric
      Rings.

## Docs

- [ ] Once the tcpdump items above are resolved, update `docs/protocol.md`
      to flip their status from "inferred, not confirmed" to confirmed (or
      correct them if the capture reveals different behavior than assumed).