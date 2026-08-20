# Devialet Expert / Expert Pro UDP Protocol

Reverse-engineered by the community (not an official Devialet API), as implemented
in this app. Sources cited per-claim below; "inferred" = not directly confirmed
by a comment, test, or observed byte value in this repo — treat as lower confidence.

Based on commit `743aa71` (current `main`, working tree clean as of this doc).

## Transport

| Property | Value | Source |
|---|---|---|
| Status port (amp → app) | UDP **45454** | `DevialetController.STATUS_PORT` |
| Command port (app → amp) | UDP **45455** | `DevialetController.COMMAND_PORT` |
| Direction, status | Amp broadcasts unsolicited, ~1x/sec, to all listeners on the LAN | `DevialetStatusListener` binds `0.0.0.0:45454` with `socket.broadcast = true`, never sends anything |
| Direction, commands | App sends unicast directly to the amp's known IP | `DevialetController.sendTwice()`: `InetAddress.getByName(deviceIp)` |
| Discovery/handshake | **None.** The app never sends a query or discovery packet — it passively listens for the amp's own periodic broadcast and learns IP + name from the sender address of whatever arrives on 45454 | `MainActivity.applyStatus()`, `DevialetStatusListener` — confirmed by grep, no outbound broadcast/multicast send exists anywhere in the codebase |
| mDNS (separate mechanism) | `_spotify-connect._tcp.` service type, used only to resolve a friendlier make/model string, not for control | `AmpModelNameResolver` — see Task 3 doc; not part of the Devialet UDP protocol itself |
| Socket lifetime, commands | A brand-new `DatagramSocket()` is opened and closed (`.use {}`) for every `sendTwice()` call | `DevialetController.sendTwice()` |
| Socket lifetime, status | One long-lived socket bound for the life of the listener thread (started `onResume`, stopped `onPause`) | `DevialetStatusListener.start()/stop()`, `MainActivity.onResume()/onPause()` |
| Timeout / retry (send) | No ack is awaited. Every command is fire-and-forget, sent **twice** back-to-back with no delay between the two sends | `DevialetController.sendTwice()`: `repeat(2) { ... }` |
| Timeout / retry (receive) | No read timeout is set on the status socket (blocking `receive()`); a receive exception just loops (or exits if `stop()` was called) | `DevialetStatusListener.start()` |
| Amp-side staleness | App-side only concept: an amp not heard from for 8s is treated as offline in the UI. Not a protocol feature. | `MainActivity.ampStaleTimeoutMs = 8_000L` |
| Encryption / auth | None. Plaintext UDP, no login, no pairing. | `AndroidManifest.xml` (`usesCleartextTraffic="true"`); `DevialetController` class doc |

## Command packet structure (app → amp, port 45455)

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
porting.

### CRC16 (CRC16/CCITT-FALSE)

- Polynomial `0x1021`, initial value `0xFFFF`, no final XOR.
- Computed over exactly the first **12 bytes** (offsets 0–11) of the 142-byte
  packet — fixed constant in code, not parameterized by packet length.
- Result written big-endian into offset 12–13.
- Source: `DevialetController.crc16()`, called as `crc16(data)` from `buildCommand()`.
- **History note:** earlier code (pre commit `3aecc1a`) took an explicit
  `length` parameter; it was hardcoded to `12` at the only call site and later
  simplified to a fixed loop bound. Behavior is unchanged, just the signature.

### Volume encoding (`dbConvert`)

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

| Command | byte6 | byte7 | byte8/byte9 | Source |
|---|---|---|---|---|
| Power on | `0x01` | `0x01` | `0x00 0x00` | `DevialetController.setPower(true)` |
| Power off | `0x00` | `0x01` | `0x00 0x00` | `DevialetController.setPower(false)` |
| Mute on | `0x01` | `0x07` | `0x00 0x00` | `DevialetController.setMute(true)` |
| Mute off | `0x00` | `0x07` | `0x00 0x00` | `DevialetController.setMute(false)` |
| Set volume | `0x00` | `0x04` | `hi/lo` of the `dbConvert()`-encoded, sign-flagged 16-bit word | `DevialetController.setVolumeDb()` |
| Select source (Phono, status index 1) | `0x00` | `0x05` | `0x3F 0x80` (hardcoded, doesn't follow the general formula) | `DevialetController.selectSource()` — bytes found via Wireshark per `gnulabis/devimote` issue #2, per code comment |
| Select source (all other known inputs) | `0x00` | `0x05` | see "Source selection" below | `DevialetController.selectSource()` |

### Source selection encoding

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
   the **raw status index** as the command value directly — unverified for
   those inputs, flagged in code as "may need adjusting per-amp/firmware."
   Source: `DevialetController.SOURCE_COMMAND_VALUE`, `selectSource()`.

2. **Bit packing**, once the command value (`cmdValue`) is resolved:
   ```
   outVal = 0x4000 | (cmdValue << 5)
   byte8 (hi) = (outVal >> 8) & 0xFF
   byte9 (lo) = cmdValue > 7 ? (outVal & 0xFF) >> 1 : (outVal & 0xFF)
   ```
   The extra `>> 1` on `lo` when `cmdValue > 7` is taken as-is from the
   reverse-engineered behavior; no rationale is documented in code. Treat as
   **inferred, not confirmed** — this is a good candidate to re-verify with a
   packet capture across the full 0–14 index range before porting.

3. **Forced volume after every source switch.** Immediately after sending the
   source-select command, the app also sends `setVolumeDb(-40.0)` unconditionally
   for every source (not just some). This compensates for the amp's own
   inconsistent per-input startup volume (observed -40dB on Optical 1 vs -38dB
   on other inputs) and is a deliberate UX decision, not part of the wire
   protocol itself. Source: `DevialetController.selectSource()`,
   `SOURCE_SWITCH_VOLUME_DB`. See `docs/known-gotchas.md` (commit `88d97eb`).

### Known-unimplemented commands

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

| Offset | Length | Field | Decoding |
|---|---|---|---|
| 19 | 31 | Device (friendly) name | UTF-8, trimmed of NUL and space padding |
| 52 + i·17 | 1 | Source `i` enabled flag (i = 0..29) | ASCII `'1'` == enabled, anything else == disabled |
| 53 + i·17 | 16 | Source `i` name | UTF-8, trimmed of NUL and space padding |
| 562 | 1 (bit `0x80`) | Power state | `1` = on |
| 563 | 1 (bits `0x3C`, i.e. `>>2`) | Active source index | 0–14, matches `DevialetSource.index` used for source remapping above |
| 563 | 1 (bit `0x02`) | Mute state | `1` = muted |
| 565 | 1 | Volume (raw byte, 0–255) | `volumeDb = (volumeInt - 195) / 2.0` — **note this is a completely different formula from the command-side `dbConvert()`**, not its inverse |

Notes:
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

## Volume dB derivation, both directions

| Direction | Formula | Source |
|---|---|---|
| Command (app → amp) | Custom recursive `dbConvert()` + sign bit | `DevialetController.dbConvert()` |
| Status (amp → app) | `(volumeInt - 195) / 2.0` | `DevialetStatus.volumeDb` |

These are **not mathematical inverses of each other** as implemented — they're
two independently reverse-engineered encodings for two different packet types.
Do not assume one can be derived from the other; port both as separate,
literal transcriptions.

## Sequencing / state machine

- **No handshake.** The app can send commands the instant it has an IP — it
  does not wait for a first status broadcast before allowing control.
  (`MainActivity.requireIp` only checks that an IP string is set, not that the
  amp has ever responded.)
- **No command ordering requirement enforced or documented** other than: send
  source-select, then always follow with a forced volume set (see above) — this
  is app-level sequencing, not a protocol requirement signaled by the amp.
- **No acknowledgement is ever read.** The app has no way to know a command
  actually reached or was applied by the amp — the only feedback loop is
  passively noticing the *next* status broadcast reflect the new state (up to
  ~1s later, see debounce handling in known-gotchas.md).
- **Multi-amp on one LAN:** every amp's broadcast is processed regardless of
  which one is "selected" — used to build the discovery/picker list — but only
  the broadcast whose sender IP matches the currently selected amp updates the
  live UI (volume/mute/power/source). Source: `MainActivity.applyStatus()`.

## Edge cases handled in code

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

- Exact meaning of the `lo >> 1` bit-shift quirk in source selection when
  `cmdValue > 7` — no rationale in code or commit history.
- Whether the amp requires exactly 2 retransmits (`sendTwice`) or tolerates/needs
  more under packet loss — no loss-handling beyond the fixed double-send exists.
- Whether packet/command counters need to be *contiguous* per logical action,
  given `sendTwice()`'s two calls to `buildCommand()` each advance both
  counters independently (see "Counter caveat" above).
- SAM, Night Mode, SAM level, Bass, Treble command bytes are entirely unknown —
  will need original packet capture work, not just code archaeology.
