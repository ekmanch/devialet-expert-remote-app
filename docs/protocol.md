# Devialet Expert / Expert Pro UDP Protocol

Reverse-engineered by the community (not an official Devialet API), as implemented
in this app. Sources cited per-claim below; "inferred" = not directly confirmed
by a comment, test, or observed byte value in this repo — treat as lower confidence.

Based on commit `743aa71` (current `main`, working tree clean as of this doc).

## Transport

All transport-layer properties below are **[Shared]** — the wire mechanics (ports,
socket lifetime, retry behavior, discovery, encryption) are used identically
regardless of which commands/status fields ride on top of them; nothing here
is Control- or Sound-specific.

| Property | Value | Source | Scope |
|---|---|---|---|
| Status port (amp → app) | UDP **45454** | `DevialetController.STATUS_PORT` | [Shared] |
| Command port (app → amp) | UDP **45455** | `DevialetController.COMMAND_PORT` | [Shared] |
| Direction, status | Amp broadcasts unsolicited, ~1x/sec, to all listeners on the LAN | `DevialetStatusListener` binds `0.0.0.0:45454` with `socket.broadcast = true`, never sends anything | [Shared] |
| Direction, commands | App sends unicast directly to the amp's known IP | `DevialetController.sendTwice()`: `InetAddress.getByName(deviceIp)` | [Shared] |
| Discovery/handshake | **None.** The app never sends a query or discovery packet — it passively listens for the amp's own periodic broadcast and learns IP + name from the sender address of whatever arrives on 45454 | `MainActivity.applyStatus()`, `DevialetStatusListener` — confirmed by grep, no outbound broadcast/multicast send exists anywhere in the codebase | [Shared] |
| mDNS (separate mechanism) | `_spotify-connect._tcp.` service type, used only to resolve a friendlier make/model string, not for control | `AmpModelNameResolver` — see Task 3 doc; not part of the Devialet UDP protocol itself | [Shared] |
| Socket lifetime, commands | A brand-new `DatagramSocket()` is opened and closed (`.use {}`) for every `sendTwice()` call | `DevialetController.sendTwice()` | [Shared] |
| Socket lifetime, status | One long-lived socket bound for the life of the listener thread (started `onResume`, stopped `onPause`) | `DevialetStatusListener.start()/stop()`, `MainActivity.onResume()/onPause()` | [Shared] |
| Timeout / retry (send) | No ack is awaited. Every command is fire-and-forget, sent **twice** back-to-back with no delay between the two sends | `DevialetController.sendTwice()`: `repeat(2) { ... }` | [Shared] |
| Timeout / retry (receive) | No read timeout is set on the status socket (blocking `receive()`); a receive exception just loops (or exits if `stop()` was called) | `DevialetStatusListener.start()` | [Shared] |
| Amp-side staleness | App-side only concept: an amp not heard from for 8s is treated as offline in the UI. Not a protocol feature. | `MainActivity.ampStaleTimeoutMs = 8_000L` | [Shared] |
| Encryption / auth | None. Plaintext UDP, no login, no pairing. | `AndroidManifest.xml` (`usesCleartextTraffic="true"`); `DevialetController` class doc | [Shared] |

## Command packet structure (app → amp, port 45455) — [Shared]

The overall 142-byte envelope (header, counters, CRC, padding) is generic
plumbing used by every command regardless of family — [Shared]. Only
`byte6`/`byte7`/payload values (see command table below) differ per
Control/Sound command.

Fixed-size **142-byte** packet. All multi-byte fields big-endian.

| Offset | Length | Field | Notes |
|---|---|---|---|
| 0–1 | 2 | Magic / header | Constant `0x44 0x72` (ASCII "Dr") on every command | 
| 2–3 | 2 | Packet counter | Big-endian uint16, increments per packet sent (wraps 0xFFFF → 0), shared across all command types | 
| 4–5 | 2 | Command counter | Big-endian uint16, increments per *logical* command (see caveat below), same wrap behavior | 
| 6 | 1 | `byte6` | Command family selector (see command table) |
| 7 | 1 | `byte7` | Command sub-selector |
| 8–9 | 2 | Payload (`byte8`, `byte9`) | Command-specific value, defaults to `0x00 0x00` when unused |
| 10–11 | 2 | *(unused)* | Left as zero-initialized `ByteArray` default | 
| 12–13 | 2 | CRC16 | Big-endian, CRC16/CCITT-FALSE over bytes 0–11 (see below) |
| 14–141 | 128 | *(unused/padding)* | Zero-filled; packet is always allocated at exactly 142 bytes regardless of command | 

Source: `DevialetController.buildCommand()`.

**Counter caveat (inferred, not confirmed):** `sendTwice()` calls `buildCommand()`
twice per logical command, and `buildCommand()` advances *both* counters each
call. So a single logical action (e.g. one mute toggle) actually consumes two
packet-counter values and two command-counter values, one pair per wire send —
the two transmitted copies of "the same" command do NOT have identical counter
bytes. Whether the amp cares about strict counter continuity, or simply
de-duplicates by payload, is not established in this codebase; this is exactly
the kind of sequencing detail worth confirming with a packet capture before
porting. **[Shared]**

### CRC16 (CRC16/CCITT-FALSE) — [Shared]

- Polynomial `0x1021`, initial value `0xFFFF`, no final XOR.
- Computed over exactly the first **12 bytes** (offsets 0–11) of the 142-byte
  packet — fixed constant in code, not parameterized by packet length.
- Result written big-endian into offset 12–13.
- Source: `DevialetController.crc16()`, called as `crc16(data)` from `buildCommand()`.
- **History note:** earlier code (pre commit `3aecc1a`) took an explicit
  `length` parameter; it was hardcoded to `12` at the only call site and later
  simplified to a fixed loop bound. Behavior is unchanged, just the signature.

### Volume encoding (`dbConvert`) — [Control]

The amp does not use a linear dB→byte mapping. `DevialetController.dbConvert()`
implements a custom recursive encoding:

```
dbConvert(0.0)  == 0x0000
dbConvert(0.5)  == 0x3F00
dbConvert(|db|) == (256 >> ceil(1 + ln(|db|)/ln(2))) + dbConvert(|db| - 0.5)   // recursive, for |db| > 0.5
```

- Input is `abs(dbValue)`; the sign is re-applied afterward as a flag bit.
- `setVolumeDb(dbIn, maxDb)`:
  1. Clamps `dbIn` to `maxDb` (default **-15.0 dB**, a deliberate safety cap — see `docs/known-gotchas.md`).
  2. Runs the clamped value through `dbConvert`.
  3. If the (clamped) dB value is negative, ORs `0x8000` into the 16-bit word (sign bit).
  4. Sends via `sendTwice(0x00, 0x04, hi, lo)` where `hi`/`lo` are the resulting word's high/low bytes.
- Source: `DevialetController.dbConvert()`, `setVolumeDb()`.
- **Status-broadcast volume uses a different, simpler formula** — see the status
  packet section below. The two are not the same encoding; do not assume symmetry.

## Command types (app → amp)

All sent via `sendTwice(byte6, byte7, byte8=0, byte9=0)` — i.e. every command
below is transmitted **twice** in immediate succession, no ack, fire-and-forget.

Every command below is **[Control]** — power, mute, volume, and source
selection are exactly the Control-tab feature set; there are no Sound-tab
wire commands in this table (see "Known-unimplemented commands" below for
why: SAM/Night Mode/Bass/Treble never got reverse-engineered byte values).

| Command | byte6 | byte7 | byte8/byte9 | Source | Scope |
|---|---|---|---|---|---|
| Power on | `0x01` | `0x01` | `0x00 0x00` | `DevialetController.setPower(true)` | [Control] |
| Power off | `0x00` | `0x01` | `0x00 0x00` | `DevialetController.setPower(false)` | [Control] |
| Mute on | `0x01` | `0x07` | `0x00 0x00` | `DevialetController.setMute(true)` | [Control] |
| Mute off | `0x00` | `0x07` | `0x00 0x00` | `DevialetController.setMute(false)` | [Control] |
| Set volume | `0x00` | `0x04` | `hi/lo` of the `dbConvert()`-encoded, sign-flagged 16-bit word | `DevialetController.setVolumeDb()` | [Control] |
| Select source (Phono, status index 1) | `0x00` | `0x05` | `0x3F 0x80` (hardcoded, doesn't follow the general formula) | `DevialetController.selectSource()` — bytes found via Wireshark per `gnulabis/devimote` issue #2, per code comment | [Control] |
| Select source (all other known inputs) | `0x00` | `0x05` | see "Source selection" below | `DevialetController.selectSource()` | [Control] |

### Source selection encoding — [Control]

Two layers of indirection, both load-bearing:

1. **Index remapping.** The source index reported in the amp's status
   broadcast (`DevialetSource.index`, 0–14) is *not* the value the amp expects
   in the select-source command. A lookup table remaps known status indices to
   command values:

   | Status broadcast index | Source | Command value |
   |---|---|---|
   | 0 | Optical 1 | -1 |
   | 1 | Phono | *(hardcoded bytes, see above — not in this map)* |
   | 2 | UPnP | 0 |
   | 3 | Roon Ready | 3 |
   | 4 | AirPlay | 4 |
   | 5 | Spotify | 5 |
   | 14 | Air (Bluetooth) | 14 |

   Any index not in the map (custom/uncommon inputs) falls through and uses
   the **raw status index** as the command value directly, flagged in code
   as "may need adjusting per-amp/firmware."
   Source: `DevialetController.SOURCE_COMMAND_VALUE`, `selectSource()`.

   **Real-device finding** (Samsung Galaxy S25, 2026-08-20 — commit: TBD,
   to be added once committed): sending status index 9 (unmapped, so
   `cmdValue = 9` via this raw-index fallback) resulted in the amp's own
   display showing "Air" — the same source selected by status index 14
   (`cmdValue = 14`, the documented Air/Bluetooth mapping). These are **not**
   the same wire bytes (`0x41 0x10` for `cmdValue = 9` vs `0x41 0x60` for
   `cmdValue = 14`), so index 9 is *not* confirmed to genuinely mean "Air" —
   the more likely explanation is that raw index 9 doesn't correspond to any
   enabled input on this particular amp's configuration, and the command was
   a no-op that left the display showing whatever was already selected. This
   wasn't isolated with a distinct starting source, so **treat the raw-index
   fallback for unmapped inputs as still unverified** — this one data point
   is not evidence it's safe to rely on generically. Worth re-testing with a
   distinct starting source and/or a packet capture before depending on it.

2. **Bit packing**, once the command value (`cmdValue`) is resolved:
   ```
   outVal = 0x4000 | (cmdValue << 5)
   byte8 (hi) = (outVal >> 8) & 0xFF
   byte9 (lo) = cmdValue > 7 ? (outVal & 0xFF) >> 1 : (outVal & 0xFF)
   ```
   The extra `>> 1` on `lo` when `cmdValue > 7` is taken as-is from the
   reverse-engineered behavior; no rationale is documented in code.

   **Confirmed against real device** (Samsung Galaxy S25, 2026-08-20 —
   commit: TBD, to be added once committed) for `cmdValue = 14` (Air/
   Bluetooth, status index 14): the amp's own display showed "Air" after
   this command, matching the intended selection — so the `>7` branch's
   formula works correctly for this one value. The exact *rationale* for the
   `>> 1` is still undocumented, and the branch hasn't been exercised across
   the full 8–15 `cmdValue` range (see the index-9 finding above, which
   muddies rather than confirms the fallback path specifically) — not yet
   verified via packet capture.

3. **Forced volume after every source switch.** Immediately after sending the
   source-select command, the app also sends `setVolumeDb(-40.0)` unconditionally
   for every source (not just some). This compensates for the amp's own
   inconsistent per-input startup volume (observed -40dB on Optical 1 vs -38dB
   on other inputs) and is a deliberate UX decision, not part of the wire
   protocol itself. Source: `DevialetController.selectSource()`,
   `SOURCE_SWITCH_VOLUME_DB`. See `docs/known-gotchas.md` (commit `88d97eb`).

### Known-unimplemented commands — [Sound]

SAM, Night Mode, Bass, and Treble are all Sound-tab-only features per
`docs/app-overview.md` — tagged [Sound] in full, out of scope for this phase.

The UI has controls for SAM (on/off + level 0–100%), Night Mode (on/off), Bass
and Treble (-18..+18 dB) — **none of these send anything over the wire**. The
command bytes haven't been reverse-engineered; toggling them only updates local
UI state. Explicitly stubbed out with TODOs in `DevialetController.kt` (lines
154–198) rather than guessed, specifically to avoid sending unverified bytes
that could do something unintended to the amp. Anyone porting this needs to
either replicate this "UI-only" behavior or do the packet-sniffing work first.

## Status packet structure (amp → app, port 45454)

Received via a single non-blocking-free `receive()` loop on a 2048-byte buffer;
packets shorter than **566 bytes** are silently discarded (treated as
malformed/irrelevant). Source: `DevialetStatusListener.parseStatus()`.

The device name field is [Shared] (used by both discovery and either tab's
header display); the source list and power/mute/volume/active-source fields
are [Control] — the source picker, power toggle, mute toggle, and volume
display are all Control-tab UI per `docs/app-overview.md`. No status fields
here carry SAM/Night Mode/Bass/Treble state — those are local-UI-only
([Sound]) and never reported by the amp at all.

| Offset | Length | Field | Decoding | Scope |
|---|---|---|---|---|
| 19 | 31 | Device (friendly) name | UTF-8, trimmed of NUL and space padding | [Shared] |
| 52 + i·17 | 1 | Source `i` enabled flag (i = 0..29) | ASCII `'1'` == enabled, anything else == disabled | [Control] |
| 53 + i·17 | 16 | Source `i` name | UTF-8, trimmed of NUL and space padding | [Control] |
| 562 | 1 (bit `0x80`) | Power state | `1` = on | [Control] |
| 563 | 1 (bits `0x3C`, i.e. `>>2`) | Active source index | 0–14, matches `DevialetSource.index` used for source remapping above | [Control] |
| 563 | 1 (bit `0x02`) | Mute state | `1` = muted | [Control] |
| 565 | 1 | Volume (raw byte, 0–255) | `volumeDb = (volumeInt - 195) / 2.0` — **note this is a completely different formula from the command-side `dbConvert()`**, not its inverse | [Control] |

Notes: **[Shared]** (general parsing behavior, applies to the whole packet regardless of which fields are read)
- The source table is a **fixed 30-slot array** (indices 0–29), regardless of
  how many the amp actually reports as enabled — disabled slots are still
  parsed and kept (just flagged `isEnabled = false`), so the app can show
  "enabled sources" as a filtered view. Source: `parseStatus()` loop `for (i in 0 until 30)`.
  This 30-slot count and the exact byte layout are read directly from the
  code, not independently re-verified against a live packet capture in this
  pass — flagged here as **taken from code, not cross-checked against raw
  bytes**.
- Minimum length check (566 bytes) implies the last read field (volume at
  offset 565) is the effective minimum-size driver; no explicit upper bound is
  enforced (buffer is 2048 bytes, excess is simply unread).
- No checksum/CRC validation is performed on incoming status packets — the app
  trusts length + successful field extraction as "valid enough."

## Volume dB derivation, both directions — [Control]

| Direction | Formula | Source |
|---|---|---|
| Command (app → amp) | Custom recursive `dbConvert()` + sign bit | `DevialetController.dbConvert()` |
| Status (amp → app) | `(volumeInt - 195) / 2.0` | `DevialetStatus.volumeDb` |

These are **not mathematical inverses of each other** as implemented — they're
two independently reverse-engineered encodings for two different packet types.
Do not assume one can be derived from the other; port both as separate,
literal transcriptions.

## Sequencing / state machine — [Shared]

General send/receive sequencing rules apply regardless of which command
family is involved — [Shared] as a whole, except the source-select →
forced-volume ordering rule, which is [Control] (both halves of that
sequence are Control-tab actions).

- **No handshake.** The app can send commands the instant it has an IP — it
  does not wait for a first status broadcast before allowing control.
  (`MainActivity.requireIp` only checks that an IP string is set, not that the
  amp has ever responded.)
- **No command ordering requirement enforced or documented** other than: send
  source-select, then always follow with a forced volume set (see above) — this
  is app-level sequencing, not a protocol requirement signaled by the amp. **[Control]**
- **No acknowledgement is ever read.** The app has no way to know a command
  actually reached or was applied by the amp — the only feedback loop is
  passively noticing the *next* status broadcast reflect the new state (up to
  ~1s later, see debounce handling in known-gotchas.md).
- **Multi-amp on one LAN:** every amp's broadcast is processed regardless of
  which one is "selected" — used to build the discovery/picker list — but only
  the broadcast whose sender IP matches the currently selected amp updates the
  live UI (volume/mute/power/source). Source: `MainActivity.applyStatus()`.

## Edge cases handled in code — [Shared]

All rows below are general transport/parsing robustness behavior, not tied to
any specific command family — [Shared] throughout.

| Case | Handling | Source |
|---|---|---|
| Status packet < 566 bytes | Dropped (`return null`), no crash, no retry | `DevialetStatusListener.parseStatus()` |
| Any exception during status parse (bad encoding, out-of-bounds, etc.) | Caught broadly, packet dropped, listener keeps running | `parseStatus()` try/catch |
| Socket bind/setup failure (e.g. port in use) | Caught; app silently loses live status but direct control commands still work since they don't depend on this listener | `DevialetStatusListener.start()` outer try/catch, comment explicit about this tradeoff |
| `receive()` throws while still running | Loop continues (treated as transient); loop exits cleanly if `stop()` was called concurrently | `DevialetStatusListener.start()` |
| Command send fails (e.g. no route to host) | Caught via `runCatching {}` at every call site in `MainActivity`, silently swallowed — no user-facing error surfaced | e.g. `network.submit { runCatching { controller.setMute(...) } }` |
| Duplicate/out-of-order status broadcasts | Not de-duplicated or sequenced — each processed independently as "the current truth"; UI simply reflects whatever arrived most recently, with debounce windows (see `docs/known-gotchas.md`) to avoid visibly jittering after a locally-initiated change | `MainActivity.applyStatus()` |
| No IP selected yet | Every control action gated behind `requireIp {}`, shows a toast instead of sending | `MainActivity.requireIp()` |

## Open questions / worth confirming before porting

- ~~Exact meaning of the `lo >> 1` bit-shift quirk in source selection when
  `cmdValue > 7`~~ — **confirmed against real device** (Samsung Galaxy S25,
  2026-08-20 — commit: TBD, to be added once committed) for `cmdValue = 14`
  (Air/Bluetooth): the formula as documented works correctly. The *rationale*
  for the shift is still undocumented, and it hasn't been exercised for
  other `cmdValue > 7` values. **[Control]**
- **New, from the same test session:** status index 9 (unmapped, raw-index
  fallback, `cmdValue = 9`) and status index 14 (`cmdValue = 14`) sent
  different wire bytes but the amp displayed "Air" after both. Likely a
  no-op on the unmapped index rather than a genuine equivalence — not
  isolated or confirmed, worth re-testing with a distinct starting source.
  See "Source selection encoding" above. **[Control]**
- Whether the amp requires exactly 2 retransmits (`sendTwice`) or tolerates/needs
  more under packet loss — no loss-handling beyond the fixed double-send exists. **[Shared]**
- Whether packet/command counters need to be *contiguous* per logical action,
  given `sendTwice()`'s two calls to `buildCommand()` each advance both
  counters independently (see "Counter caveat" above) — **still inferred,
  not confirmed**; real-device testing so far hasn't included a packet
  capture, so amp tolerance of this counter scheme vs. a strict-continuity
  requirement remains unverified either way. **[Shared]**
- SAM, Night Mode, SAM level, Bass, Treble command bytes are entirely unknown —
  will need original packet capture work, not just code archaeology. **[Sound]**
