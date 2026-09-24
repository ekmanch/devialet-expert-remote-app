# Devialet Expert / Expert Pro UDP Protocol

Reverse-engineered by the community (not an official Devialet API). Sources
cited per-claim below; "inferred" = not directly confirmed by a comment,
test, or observed byte value — treat as lower confidence.

Provenance, in order of authority:

1. **Real-device measurements from the KDE Plasma widget**
   (`devialet-expert-remote-kde`, Rust `crates/protocol` + daemon, v1.0.4),
   against an Expert 140 Pro (`192.168.0.22`, UDP name "My Devialet-ETH").
   Facts established there *after* the Kotlin app are marked **★**. That
   widget is the most battle-tested implementation of this protocol; when
   this doc and the Kotlin-derived text disagree, the ★ fact wins.
2. The original Kotlin app (`devialet-expert-remote`, `main` @ `743aa71`),
   whose class/function names are cited as `DevialetController.…` etc.
3. This repo's Dart networking layer (`lib/networking/`, `main` @ `3c0b8e0`),
   reconciled against 1 and 2 on 2026-09-15 — see "Code vs. doc
   reconciliation" at the end. Where the Dart code disagrees with a fact
   here it is flagged inline with **⚠ Dart:** and listed in that section;
   the doc describes the target behaviour, not the current code.
4. **The 2026-09-19 live verification run** against the same amp from
   this repo (`docs/protocol-verification-2026-09-19.md`, raw log in
   `docs/captures/`, harness in `tool/protocol_probe/`). It settled the
   three open tcpdump questions and several "inferred" items; facts from
   it are marked **✔** and rank with ★.

## Transport

All transport-layer properties below are **[Shared]** — the wire mechanics
(ports, socket lifetime, retry behavior, discovery, encryption) are used
identically regardless of which commands/status fields ride on top of them.

| Property | Value | Source | Scope |
|---|---|---|---|
| Status port (amp → app) | UDP **45454** | `DevialetController.STATUS_PORT`; `DevialetProtocol.statusPort` | [Shared] |
| Command port (app → amp) | UDP **45455** | `DevialetController.COMMAND_PORT`; `DevialetProtocol.commandPort` | [Shared] |
| Direction, status | Amp broadcasts unsolicited to all listeners on the LAN. ✔ **5 Hz steady, idle or busy**: 150 packets in 30 s, inter-packet gap 197–204 ms (2026-09-19; the older "~1 Hz nominal" was wrong). ✔ Over Wi-Fi the same broadcast arrived 8–164 ms (median 66) after the wired copy and **about half were lost** on the desktop's adapter — a phone measurement is still owed (TODO.md) | `DevialetStatusListener` binds `0.0.0.0:45454` with `socket.broadcast = true`, never sends; KDE daemon capture | [Shared] |
| Direction, commands | App sends unicast directly to the amp's known IP | `DevialetController.sendTwice()`; `DevialetUdpTransport.sendTwice()` | [Shared] |
| Discovery/handshake | **None.** The app never sends a query or discovery packet — it passively listens for the amp's own periodic broadcast and learns IP + name from the sender address of whatever arrives on 45454 | `MainActivity.applyStatus()`, `DevialetStatusListener`; confirmed by grep, no outbound broadcast/multicast send exists | [Shared] |
| mDNS (separate mechanism) | `_spotify-connect._tcp.local.` service type, used only to resolve a friendlier make/model string, not for control — see "mDNS model-name resolution" | `AmpModelNameResolver`; KDE `crates/protocol/src/model_name.rs` | [Shared] |
| Socket lifetime, commands | A brand-new socket is opened and closed for every logical command (both wire sends share it) | `DevialetController.sendTwice()`; `DevialetUdpTransport.sendTwice()` | [Shared] |
| Socket lifetime, status | One long-lived socket bound with `SO_REUSEADDR` for the life of the listener | `DevialetStatusListener.start()/stop()`; `DevialetUdpTransport.bindAndListen()` | [Shared] |
| Timeout / retry (send) | No ack is awaited. Every command is fire-and-forget, sent **exactly twice** back-to-back with no delay. Sending to an offline IP does not fail; the datagram is just lost. ✔ The amp needs only one copy (20/20 single sends on Ethernet), but Wi-Fi dropped 2/20 single sends and 0/10 double sends, so the duplicate stays as cheap loss insurance; **no adaptive retry** (decision 2026-09-19) | `DevialetController.sendTwice()`; `DevialetClient._sendTwice()` | [Shared] |
| Timeout / retry (receive) | No read timeout on the status socket; a receive error just loops | `DevialetStatusListener.start()`; `DevialetUdpTransport.bindAndListen()` | [Shared] |
| Amp-side staleness | App-side only concept: an amp not heard from for **8 s** is offline, re-evaluated on a 1 s tick against a **monotonic clock**. Not a protocol feature | `MainActivity.ampStaleTimeoutMs = 8_000L`; KDE daemon `online = last_seen < 8 s` | [Shared] |
| Encryption / auth | None. Plaintext UDP, no login, no pairing, no handshake gate: commands may be sent the instant an IP is known | `AndroidManifest.xml` (`usesCleartextTraffic="true"`) | [Shared] |

## Command packet structure (app → amp, port 45455) — [Shared]

Fixed-size **142-byte** packet. All multi-byte fields big-endian. The
envelope (header, counters, CRC, padding) is generic plumbing used by
every command; only `byte6`/`byte7`/payload differ per command.

| Offset | Length | Field | Notes |
|---|---|---|---|
| 0–1 | 2 | Magic / header | Constant `0x44 0x72` (ASCII "Dr") on every command |
| 2–3 | 2 | Packet counter | uint16, advances per **wire send**, wraps 0xFFFF → 0 |
| 4–5 | 2 | Command counter | uint16, advances per **wire send** (see counter caveat), same wrap |
| 6 | 1 | `byte6` | Command family selector (see command table) |
| 7 | 1 | `byte7` | Command sub-selector |
| 8–9 | 2 | Payload (`byte8`, `byte9`) | Command-specific value, `0x00 0x00` when unused |
| 10–11 | 2 | *(unused)* | Zero |
| 12–13 | 2 | CRC16 | Big-endian, CRC16/CCITT-FALSE over bytes 0–11 only (see below) |
| 14–141 | 128 | *(padding)* | Zero-filled; packet is always exactly 142 bytes |

Source: `DevialetController.buildCommand()`; `CommandPacket.encode()`.

★ **Golden vectors** (counters 0,0) — all three pinned as literal-byte
regression tests in `test/networking/` since Task 1.1.1 (2026-09-19),
alongside the status byte `111 → −42.0` and every source byte pair below:

- Power on: `44 72 00 00 00 00 01 01 00 00 00 00 A0 BD` (+128 zero bytes)
- CRC of ASCII `"123456789"` = `0x29B1`
- CRC of 12 zero bytes = `0x84F9`

**Counters — ✔ ignored by the amp (2026-09-19).** `sendTwice()` builds two
packets per logical command and advances *both* counters on each build, so
the two wire copies of "the same" command do NOT carry identical counter
bytes (nor identical CRCs); both the Kotlin app and the Dart
`PacketCounters` start at (0,0) per process, and ★ the KDE CLI restarts at
(0,0) on every invocation. The live run settled why none of that matters:
counters frozen at (0,0) on every send (6/6 applied), arbitrary,
decreasing and mismatched values incl. `0xFFFF` (6/6), and byte-identical
copies ×2 and ×5 (4/4) were all accepted — the amp neither checks
contiguity nor de-duplicates. The Dart layer keeps the original behaviour
for wire fidelity; nothing depends on it and no persisted counter is
needed across processes.

### CRC16 (CRC16/CCITT-FALSE) — [Shared]

- Polynomial `0x1021`, initial value `0xFFFF`, no reflection, no final XOR.
- Computed over exactly the first **12 bytes** (offsets 0–11) — a fixed
  constant, not parameterized by packet length.
- Result written big-endian into offsets 12–13.
- Source: `DevialetController.crc16()`; `crc16CcittFalse()` in
  `lib/networking/crc16.dart` (`DevialetProtocol.crcCoveredLength = 12`).
- ✔ **The amp checks it** (2026-09-19): a packet with a corrupted CRC is
  dropped (0/5 trials, single and double send), and so is one whose byte 0
  is not `0x44`. The 128 zero bytes of padding are **not** required — a
  14-byte packet (header through CRC) was applied — but keep sending 142
  bytes; it is what every implementation and the original capture used.

### Volume encoding (`dbConvert`) — [Control]

The amp does not use a linear dB→byte mapping. The command side uses a
custom recursive encoding on `|db|`:

```
dbConvert(0.0)  == 0x0000
dbConvert(0.5)  == 0x3F00
dbConvert(|db|) == (256 >> ceil(1 + log2(|db|))) + dbConvert(|db| - 0.5)   // |db| > 0.5
```

Reference values: `1.0 → 0x3F80`, `15.0 → 0x4170`, `40.0 → 0x4220`
(★ KDE test vectors; reproduced by `VolumeCodec.dbConvert` on 2026-09-15).

✔ **What the recursion actually computes (2026-09-19):** the sign-flagged
word is exactly the **top 16 bits of the IEEE-754 float32** of the signed
dB value (a `bfloat16` truncation): `−40.0f = 0xC2200000 → C2 20`,
`15.0f = 0x41700000 → 41 70`. Verified identical to `dbConvert` on every
0.5 dB step from −100 to +100 dB (`tool/protocol_probe/bf16_check.py`).
This is the explanation, not a licence to rewrite: the literal port and
its pinned vectors stay. The amp quantizes on its side too — the exact
word for −40.25 (`C2 21`) was applied as −40.5 (one sample).

- The sign is applied afterwards: if the dB value is negative, OR `0x8000`
  into the 16-bit word. Sent as `byte6=0x00, byte7=0x04, byte8=hi, byte9=lo`.
- ★ **Port-critical — non-half-step input.** The literal recursion only
  terminates on exact 0.5 dB steps. The Rust port rounds the input to the
  **nearest** 0.5 dB and recurses on an integer step count: byte-identical
  to the formula on every exact step, never hangs (e.g. −15.3 → the −15.5
  word), and immune to floating-point drift in either direction.
  **Dart:** `VolumeCodec.dbConvert` matches the Rust behaviour since Task
  1.1.0 (quantize once at entry, recurse on the integer step count; the
  rounding cases are pinned in `test/networking/volume_codec_test.dart`).
- **Ceiling.** The protocol accepts up to **+30 dB**; nothing on the wire
  stops a dangerous value, so the clamp is a client duty. History: the
  Kotlin app clamped at 0 dB (too loud), then −15 dB (`docs/known-gotchas.md`
  #6). ★ **Owner decision 2026-09-14: the ceiling is a persisted setting,
  default −10.0 dB**, alongside a floor (default −50.0) and a startup volume
  (default −40.0), all over −96..0; the ceiling is enforced inside the
  command constructor as a *required* parameter with an explicit "none"
  for unbounded, so no caller can forget it. The floor is a UI-only
  concept and never reaches the wire.
  **⚠ Dart:** `VolumeCodec.defaultSafetyMaxDb` is still **−15.0**, is an
  *optional defaulted* parameter on `setVolumeDb`/`setVolume`, and
  `volume_codec_test.dart` pins −15.0 ("is not silently regressed"). This
  is deliberately unchanged in the 2026-09-15 doc pass: change it once, in
  the shared settings object, with the UI range and that test, in Task
  3.4.7 / 3.4.8 (value) and Task 1.1.3 (required parameter) — not as a
  drive-by edit.
- **Status-broadcast volume uses a different, simpler formula** — see the
  status packet section. The two are not inverses; do not assume symmetry.

## Command types (app → amp)

All sent via `sendTwice(byte6, byte7, byte8=0, byte9=0)` — every command
is transmitted **twice** in immediate succession, no ack, fire-and-forget.

Every command below is **[Control]**. There are no Sound-tab wire commands
(see "Known-unimplemented commands").

| Command | byte6 | byte7 | byte8/byte9 | Source | Scope |
|---|---|---|---|---|---|
| Power on | `0x01` | `0x01` | `0x00 0x00` | `setPower(true)`; `CommandPayloads.powerOn` | [Control] |
| Power off | `0x00` | `0x01` | `0x00 0x00` | `setPower(false)`; `CommandPayloads.powerOff` | [Control] |
| Mute on | `0x01` | `0x07` | `0x00 0x00` | `setMute(true)`; `CommandPayloads.muteOn` | [Control] |
| Mute off | `0x00` | `0x07` | `0x00 0x00` | `setMute(false)`; `CommandPayloads.muteOff` | [Control] |
| Set volume | `0x00` | `0x04` | `hi/lo` of the `dbConvert()`-encoded, sign-flagged word | `setVolumeDb()`; `CommandPayloads.setVolume` | [Control] |
| Select source, status index 1 | `0x00` | `0x05` | `0x3F 0x80` hardcoded — ✔ it is `float32(1.0)`, see "Source selection encoding" | `selectSource()` — bytes found via Wireshark per `gnulabis/devimote` issue #2; `CommandPayloads._hardcodedSelectPayload` | [Control] |
| Select source, all other indices | `0x00` | `0x05` | see "Source selection encoding" | `selectSource()`; `SourceMapping` | [Control] |

### Volume and mute are independent — [Control]

★ Separate opcodes; a volume packet carries no mute bit, so **a volume
command does not unmute**. The KDE widget relies on this to correct a muted
amp's volume (e.g. after a ceiling change) without unmuting it. Any
"auto-unmute on volume change" behaviour is a client decision layered on
top (see TODO.md, volume interaction), not a wire effect.

### Source selection encoding — [Control]

Two layers of indirection, both load-bearing:

1. **Index remapping.** The source index reported in the status broadcast
   is *not* the value the amp expects in the select-source command
   (`docs/known-gotchas.md` #3). A lookup table remaps known status
   indices to command values:

   | Status index | Kotlin "command value" (historical) | Wire bytes 8–9 | Confidence |
   |---|---|---|---|
   | 0 | −1 | `FF E0` | confirmed (KDE); ✔ = float NaN → slot 0 |
   | 1 | *(hardcoded, not in the map)* | `3F 80` | confirmed on **two** amps (KDE) |
   | 2 | 0 | `40 00` | confirmed (KDE) |
   | 3 | 3 | `40 60` | confirmed (KDE); ✔ = float 3.5, truncated to 3 |
   | 4 | 4 | `40 80` | confirmed (KDE) |
   | 5 | 5 | `40 A0` | confirmed (KDE) |
   | 14 | 14 | `41 60` | confirmed (Galaxy S25 2026-08-20; KDE) |
   | other | — | `bfloat16(index)`, e.g. 9 → `41 10`, 16 → `41 80`, 29 → `41 E8` | ✔ 6–15 confirmed by the 2026-09-19 run (the old formula coincided there); 16–29 predicted by the float model, **not confirmable on the owner's unit** (Task 1.1.4, 2026-09-24) |

   Source: `DevialetController.SOURCE_COMMAND_VALUE` (Kotlin, the
   "command value" column); **Dart since Task 1.1.4 (2026-09-24):**
   `SourceMapping._pinnedPayloadByStatusIndex` holds the six confirmed
   pairs as **literal bytes** (two of them are not `bfloat16(index)`:
   slot 0 is NaN and slot 3 is 3.5) and everything else is
   `SourceMapping.encodeSelectPayload` = the top 16 bits of
   `float32(index)`; index 1's literal lives in `CommandPayloads`. The
   Kotlin-era "command value" indirection and its signed bit-packing are
   gone from the code; `tool/protocol_probe/proto.py::src_payload` mirrors
   the same two tiers and `xcheck.dart` proves both emit identical bytes
   for 0–5, 9, 14, 16 and 29.

   **Status-side limit:** the active-source field at offset 563 is 4 bits
   wide (`0x3C >> 2`, 0–15), so a slot ≥ 16 can be *selected* by the
   command but never *confirmed* by a broadcast — the pending mask would
   expire at 400 ms and the card snap back. No known unit enables such a
   slot; recorded so the symptom is not mistaken for a dropped command.

   ★ **Names are per-unit, numbers are not.** The names historically
   attached to this table ("Optical 1", "Phono", "UPnP", "Roon Ready",
   "AirPlay", "Spotify", "Air") were what one reference amp happened to
   have configured at each slot when the Kotlin table was written. Sending
   index 1's hardcoded bytes to a *second* Expert Pro 140 selected that
   amp's slot 1, which it calls "UPnP" (the first amp calls it "Phono");
   every other name on that amp was likewise shifted by one, and "Phono"
   did not appear in its 30 slots at all (KDE
   `docs/devialet_source_mapping.md`, 2026-08-21). The numeric mapping is
   confirmed and portable; the names are not a protocol constant. **The
   only authoritative name for an index is that amp's own live broadcast**
   (the source-name field at `53 + i·17`). Never key anything on a name
   assumed for an index, and never hardcode a per-index name in code.
   **Dart:** `source_mapping.dart` and `command_payloads.dart` carry
   numbers only since Task 1.1.2 (2026-09-19); the index-1 special case is
   `CommandPayloads.hardcodedSelectStatusIndex`. The only names left in
   `test/` are `status_packet_test.dart` fixtures written into a synthetic
   broadcast and read back, which is exactly the live-name path.

   ✔ **What the bytes actually are (2026-09-19 live run).** The payload is
   the **top 16 bits of the IEEE-754 float32 of the slot index** — the
   same encoding as the volume word — and the amp **truncates toward zero**
   and selects that slot if it is enabled: `40 40` (3.0) → slot 3, `00 00`
   (0.0) → slot 0, `3F C0` (1.5) → slot 1, `40 30` (2.75) → slot 2,
   `40 90` (4.5) → slot 4. NaN (`FF E0`, the table's "−1") and negative
   values (`BF 80` = −1.0) select slot 0. Read that way the table is not a
   mapping at all: 1 → 1.0, 2 → 2.0, 4 → 4.0, 5 → 5.0, 14 → 14.0 are
   literal, index 3's `40 60` is 3.5 (truncated to 3) and index 0's `FF E0`
   is NaN (→ 0). The table stays because every entry is confirmed on two
   amps and harmless; the finding matters for what lies *outside* it.

   **Raw-index fallback — ✔ resolved (2026-09-19).** The Galaxy S25
   observation of 2026-08-20 (index 9 left the display on "Air") was real,
   not a no-op: on this unit **slot 9 is a firmware alias of slot 14**.
   `41 10` (9.0) switched to 14 from slots 0, 2 and 3 (3/3), while every
   other disabled or out-of-range index — 5, 6, 7, 8, 10, 11, 12, 13, 16,
   29, 30, 100 — was a **no-op** (12/12 from slot 0; 5.0 from slot 14
   too). So an index the broadcast flags as enabled selects that slot, a
   disabled one does nothing, except for unit-specific aliases. Whether
   the alias exists on other units is unknown; a client that only offers
   indices flagged enabled (`52 + i·17 == '1'`) can never reach it.
   **Unmapped-but-enabled indices could not be exercised** — this unit
   enables only 0–4 and 14, all mapped — but the float model predicts
   `bfloat16(index)` for them.

2. **Bit packing**, once the command value (`cmdValue`) is resolved:
   ```
   word  = top 16 bits of IEEE-754 float32(index)   // bfloat16(index)
   byte8 = word >> 8, byte9 = word & 0xFF
   ```
   Historical note (retired 2026-09-24, Task 1.1.4): the Kotlin/KDE
   encoder was `outVal = 0x4000 | (cmdValue << 5)`, with the low byte
   halved for `cmdValue > 7`. ✔ 2026-09-19 explained why it worked: for
   6–7 it yields `float32(v)` directly and for 8–15 the halving lands on
   `float32(v)` too (`41 60` = 14.0; without it `41 C0` = 24.0 was a
   no-op), while for ≥ 16 it produced 32.0, 36.0, … — silent no-ops. The
   float encoding gives the same bytes for 6–15 (pinned by
   `command_payloads_test.dart` against the retired formula inlined) and
   16.0…29.0 for the rest.
   Source: `SourceMapping.encodeSelectPayload`.

3. **Forced volume after every source switch** — see "Per-input volume
   memory" below.

### Per-input volume memory and the forced post-switch volume — [Control]

The amp remembers a volume per input (−40 on Optical 1 vs −38 on others
were observed), which reads as random to a user. Every source switch is
therefore followed by a volume command: source×2 then volume×2, same
counter sequence, ★ **zero delay needed** (6/6 measured; no settling
period between the two). Historically fixed at **−40 dB**
(`docs/known-gotchas.md` #5); ★ the KDE widget made it the **startup
volume setting** (default −40), also applied after a widget-initiated
power-on. This is a product decision masking a hardware quirk — do not
optimise it away as a redundant network call.
**⚠ Dart:** `DevialetClient.selectSource` hardcodes
`sourceSwitchVolumeDb = -40.0` and sends it through the −15 default
ceiling; it becomes the startup-volume setting in Task 3.4.8 (TODO.md).

### Known-unimplemented commands — [Sound]

SAM, Night Mode, SAM level, Bass, Treble: command bytes were never
reverse-engineered, and no status field carries them. The Kotlin Sound tab
is local state only (resets to `samLevel 70`, `bass 0`, `treble 0`,
`samOn true`, `nightOn false` every launch); explicitly stubbed with TODOs
in `DevialetController.kt` rather than guessed, to avoid sending
unverified bytes. Not attempted in the KDE widget either. Either replicate
the "UI-only" behaviour honestly labelled, or do the capture first
(TODO.md, protocol verification).

## Status packet structure (amp → app, port 45454)

Packets shorter than **566 bytes** are silently discarded. Inbound packets
are not CRC-checked. ★ Layout verified byte-for-byte over 84 packets on
the real amp (KDE). Source: `DevialetStatusListener.parseStatus()`;
`DevialetStatus.tryParse()` (matches this table exactly).

| Offset | Length | Field | Decoding | Scope |
|---|---|---|---|---|
| 19 | 31 | Device (friendly) name | UTF-8 (lossy), trimmed of NUL and space padding | [Shared] |
| 52 + i·17 | 1 | Source `i` enabled flag (i = 0..29) | ASCII `'1'` == enabled, anything else == disabled | [Control] |
| 53 + i·17 | 16 | Source `i` name | UTF-8, trimmed of NUL and space padding; 16-char max | [Control] |
| 562 | bit `0x80` | Power state | `1` = on | [Control] |
| 563 | bits `0x3C` (`>> 2`) | Active source index | 0–15 by mask; observed 0–14 | [Control] |
| 563 | bit `0x02` | Mute state | `1` = muted | [Control] |
| 565 | 1 | Volume (raw byte) | **`dB = (raw − 195) / 2`**, exact: 195 = 0 dB, 165 = −15, 111 = −42 | [Control] |

Notes **[Shared]**:
- The source table is a **fixed 30-slot array** including disabled slots;
  `selected` is derived per slot from the active index. Show "enabled
  sources" as a filtered view.
- Minimum length 566 is driven by the last read field (volume at 565); no
  upper bound is enforced (2048-byte buffer, excess unread).
- Because the status formula is exact, **equality on the raw byte (or its
  decoded dB) is safe for confirmation matching** — no epsilon needed.
  This is what the pending-command mask's "confirmed" channel keys on.
- No status field carries SAM/Night Mode/Bass/Treble.

## Volume dB derivation, both directions — [Control]

| Direction | Formula | Source |
|---|---|---|
| Command (app → amp) | Custom recursive `dbConvert()` + sign bit | `DevialetController.dbConvert()`; `VolumeCodec.encodeCommandWord` |
| Status (amp → app) | `(raw − 195) / 2.0` | `DevialetStatus.volumeDb`; `VolumeCodec.decodeStatusVolume` |

These are **not mathematical inverses** — two independently
reverse-engineered encodings for two packet types. Port both as separate,
literal transcriptions.

## Timing facts — [Shared] (★ all measured on the real amp)

`DevialetClient` deliberately stops at the wire; these live in the state
owner (`lib/domain/amp_tracker.dart` constants, `docs/architecture.md`).
All timers must run on a **monotonic clock** (Rust uses `Instant`; Kotlin
`SystemClock.elapsedRealtime()`), never wall-clock time.

| Value | Meaning |
|---|---|
| 400 ms | pending-command / debounce window ("settled input") — same number in Kotlin, Flutter (`docs/known-gotchas.md` #1/#2) and KDE |
| 100–200 ms | pace of outbound commands during a sustained gesture (a different concern from the 400 ms trust window) |
| ✔ 82–200 ms (median ~95, n = 60 on Ethernet; one 297 ms over Wi-Fi) | delay until the amp's next broadcast confirms a command — bounded by the 200 ms broadcast period, not by processing |
| 8 s | staleness: `online = last_seen < 8 s`, re-evaluated on a 1 s tick |
| 15.0–18.6 s | real boot time (one sample 16.07 s; 2026-09-21 on this app: 15.00 s ×3 when the dev machine sent power-on, 15.99–16.08 s ×3 when the phone did — `docs/protocol-verification-2026-09-21-boot.md`) |
| 20 s | boot timeout (15 s made a normal boot flash "Off" first) |
| 500 ms | delay after the first "power on" broadcast before a volume command is safe (`docs/known-gotchas.md` #9); the app's send lands at +555…+615 ms and is applied by +800 ms (5/5, 2026-09-21) |
| 1500 ms | bounded fallback for the post-boot display hold |
| 0 ms | settling needed between source switch and the forced volume (6/6) |

## Post-boot firmware behaviour — [Control] (★ 21+ real boots)

Full write-ups: `docs/known-gotchas.md` #8 and #9. Summary:

- **#8 — the broadcast is wrong after boot and never self-corrects.** The
  first `power_on` packet still carries the pre-shutdown volume byte;
  ~200 ms later the broadcast reads **raw 111 = −42.0 dB** and stays there
  while the front panel reads −40 (the configurator's startup volume).
  Any volume command, any value, makes the broadcast track reality again.
  "The status *is* the wrong value — don't fix it by re-reading harder."
  This is the root cause of the Kotlin-era "amp-initiated volume changes
  aren't reflected until we send one" observation; stop looking for it in
  the client.
- **#9 — volume commands sent before the amp has applied its own startup
  volume are silently dropped.** Sweep from the first power-on packet:
  +2 ms 0/1, +100 ms 1/2, +200 ms 9/9 (but every pass had the amp applying
  at ≤ +202 ms), +500 ms 3/3, +1018/+2030 ms 1/1. Latest observed amp-side
  application: **+394 ms**. Hence 500 ms — "200 ms is the middle of the
  observed spread, not a safety margin." A user volume change inside that
  window **is** honoured (4/4 at +161…+349 ms), so a deferred send must
  re-target to the user's value, never override it.
- Commands sent while the amp is Off or Booting are dropped by the amp
  (seen even 2 ms after "On").

## Multi-amp discovery, selection, persistence — [Shared]

- Amps are keyed by **sender IP**; every broadcast updates the discovery
  map; entries are **never evicted** — a silent amp flips to
  `online = false` after 8 s. Known amps are in-memory only.
- Only the broadcast whose sender IP matches the selected amp updates the
  live control state; all broadcasts feed the picker list
  (`MainActivity.applyStatus()`).
- ★ **Auto-select-if-alone**: nothing explicitly selected **and** the user
  has never made a choice **and** exactly one amp known → that amp. With 0
  or 2+ amps, show the not-connected state; don't guess. Three-plus amps
  was never testable.
- ★ Selecting "None" must be a distinct persisted state from "never
  chosen". Android collapses both into one empty-string sentinel (harmless
  there, no auto-select); with auto-select it was a real bug: clearing the
  selection looked like "never called" and the amp was re-picked on
  restart. Persist the "has explicit selection" flag too.
- A never-heard IP is a valid selection (manual-IP fallback for other
  subnets); show that IP with the not-connected fields until a broadcast
  arrives. A persisted IP needs **no** reconciliation step: trust it and
  let staleness govern connectedness (what Android does with
  `amp_ip`/`amp_name`).
- Not-connected state: name `""`, online false, sources `[]`, power "Off".
  ★ **Beware the zero default**: a "none" state once produced
  `volume = 0.0`, which a slider clamped into range and displayed as a
  plausible "−15.0 dB". Check "is there an amp" before any clamp.

## mDNS model-name resolution — [Shared]

Not part of the Devialet UDP protocol; a separate, best-effort mechanism
for a nicer "make/model" label. No Dart implementation yet.

- Service type `_spotify-connect._tcp.local.` — not Devialet-specific, so a
  resolution is **only trusted for an IP already heard over UDP**. Match
  on the first IPv4 address. Resolved once, never re-attempted or cleared,
  and carried forward across every status re-ingestion (or the ~1 s
  broadcast wipes it). Display `modelName ?? udpName`, keeping both (model
  as label, UDP name as subtitle).
- ★ Android's `NsdManager` restart bursts (`RETRY_DELAYS_MS`,
  `STEADY_INTERVAL_MS`, for Samsung Wi-Fi power-save — see
  `docs/app-overview.md`) are an Android artefact, not an mDNS
  requirement: one continuous browse resolved in < 0.6 s on Linux.
- `parseModelName`: take the part before the first `-` (whole string if
  none), trim, empty → null; insert a space at every letter→digit and
  digit→**uppercase** boundary (digit→lowercase is not one); prefix
  "Devialet ". `Expert140Pro-K48A…local.` → "Devialet Expert 140 Pro"
  (the one real case); `2go` → "Devialet 2go"; `Phantom2Reactor900-…` →
  "Devialet Phantom 2 Reactor 900". Real two-amp mDNS is untested.

## Edge cases handled in code — [Shared]

| Case | Handling | Source |
|---|---|---|
| Status packet < 566 bytes | Dropped, no crash, no retry | `parseStatus()`; `DevialetStatus.tryParse` returns `null` |
| Any exception during status parse | Caught broadly, packet dropped, listener keeps running | `parseStatus()` try/catch; `tryParse` catch-all |
| Socket bind/setup failure (e.g. port in use) | Caught; app loses live status but direct control commands still work | `DevialetStatusListener.start()`; `bindAndListen` `catchError` |
| `receive()` throws while still running | Loop continues; exits cleanly only on `stop()` | `DevialetStatusListener.start()`; `bindAndListen` |
| Command send fails (e.g. no route to host) | Kotlin: caught at every call site, silently swallowed. Dart: `sendTwice` propagates; the domain layer must catch **and roll back the optimistic value** (a failed command must not assert an unconfirmed value indefinitely) | `MainActivity` `runCatching {}`; `DevialetUdpTransport.sendTwice` |
| Duplicate/out-of-order status broadcasts | Not de-duplicated; each is "the current truth", subject to the pending-command mask | `MainActivity.applyStatus()` |
| No IP selected yet | Every control gated; Kotlin shows a toast, Dart throws `NoDeviceIpSetException` | `MainActivity.requireIp()`; `DevialetClient._sendTwice` |

## Confirmed vs. inferred (flag before relying)

**Confirmed on the real amp:** ports and packet envelope; CRC vectors
and ✔ that the amp enforces the CRC and magic bytes; ✔ counters ignored
(contiguity, start value, duplicates); ✔ one copy suffices on Ethernet,
the double send covers Wi-Fi loss; ✔ 5 Hz broadcast, 82–200 ms
confirmation latency; every source byte pair in the table incl. the
index-1 special case and the `cmdValue = 14` (`> 7`) branch, ✔ now
understood as `float32(index)` truncated by the amp, incl. NaN/negative →
slot 0 and disabled index → no-op; ✔ the 2026-08-20 "index 9 → Air"
finding as a slot 9 → 14 alias on this unit; ✔ the volume word as
`bfloat16(dB)`; per-unit source names; the whole status layout; gotchas
#8 and #9 with their timings; source + forced volume with no delay
(26/26 more on 2026-09-19); boot time 15.0–18.6 s; volume and mute
independence.

**Inferred / unverified:** `bfloat16(index)` for an *enabled* slot
≥ 16 (no such slot on the owner's unit; the float model predicts it and
the encoder sends it since Task 1.1.4); whether the slot 9 → 14 alias exists on other units;
Wi-Fi broadcast loss/delay **on the phones** (only the desktop adapter
was measured); front-panel/remote volume changes on a running amp (never
tested); real two-amp mDNS (needs a second physical amp on the same LAN);
SAM / Night Mode / SAM level / Bass / Treble bytes (never captured).

## Code vs. doc reconciliation (2026-09-15, `lib/networking/` @ `3c0b8e0`)

Checked by reading the Dart sources and running them against the ★
vectors above. **Agrees:** ports, 142-byte envelope, counters advancing
per wire send from (0,0), CRC over 12 bytes and all three golden vectors,
every command's byte6/byte7, all seven source byte pairs incl. signed
packing of index 0, status layout and formula (`111 → −42.0`), fresh
socket per logical command, `SO_REUSEADDR` + broadcast on the listener,
drop-and-continue on short/malformed packets, source-then-volume with no
delay. **Disagrees** (each also flagged inline above and tracked in
TODO.md; nothing changed in code during the doc pass):

| # | Where | Doc / decision | Dart today | Resolution |
|---|---|---|---|---|
| 1 | Volume ceiling | Setting, default **−10.0**, required constructor parameter (owner decision 2026-09-14) | `VolumeCodec.defaultSafetyMaxDb = -15.0`, optional defaulted parameter, test pins −15 | Volume-limits phase: change constant, UI range and test together |
| 2 | `dbConvert` on non-half-step input | Round to **nearest** 0.5 dB, integer step recursion | ~~Rounded **up** (15.2 and 15.0000001 → the 15.5 word)~~ | **Resolved, Task 1.1.0** (2026-09-19) |
| 3 | Post-switch volume | Startup-volume setting (default −40) | Hardcoded `sourceSwitchVolumeDb = -40.0` | Volume-limits phase |
| 4 | Source names in code comments | Per-unit, never assume a name for an index | ~~Kotlin-era names in comments; `phonoStatusIndex` identifier~~ | **Resolved, Task 1.1.2** (2026-09-19) |
| 5 | Golden vectors in tests | `"123456789" → 0x29B1`, power-on → `A0 BD`, `1.0/15.0/40.0 → 3F80/4170/4220`, status `111 → −42.0`, all seven source byte pairs | ~~Only `0x84F9` (12 zeros) and structural checks were in the suite~~ | **Resolved, Task 1.1.1** (2026-09-19); power-off `E5 1D` added from the KDE suite |
| 6 | Send failure | Domain layer must roll back optimistic state | No domain layer yet; `sendTwice` just propagates | State-owner phase |
| 7 | Select-source fallback, indices ≥ 16 | `bfloat16(index)` (✔ float model, 2026-09-19) | ~~`0x4000 \| (i << 5)` with `>> 1` → 32.0, 36.0, … (no-ops)~~ | **Resolved, Task 1.1.4** (2026-09-24); pinned 16 → `41 80`, 29 → `41 E8`, unconfirmable on this unit |
