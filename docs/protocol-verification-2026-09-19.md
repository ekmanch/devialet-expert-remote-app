# Protocol verification run — 2026-09-19

Live run against the owner's Expert Pro 140 (`192.168.0.22`, UDP name
"My Devialet-ETH", on Ethernet) from the Linux dev machine, which sits on
the same LAN over both wired (`eno1`) and Wi-Fi (`wlan0`). Settles the
three open items of TODO.md's "Protocol verification" workstream and
several facts `docs/protocol.md` carried as "inferred". Facts from this
run are marked **✔** in `docs/protocol.md`.

- Harness: `tool/protocol_probe/` (Python, standard library).
- Raw log, every broadcast decoded and every send timestamped:
  `docs/captures/2026-09-19-protocol-verification.txt`.
- No root was available for `tcpdump`, so no pcap. The listener is an
  ordinary UDP socket on 45454 reading the raw datagrams, tagged with the
  receiving interface via `IP_PKTINFO`; for the inbound side that *is*
  the raw capture. The outbound bytes were built independently of the
  Dart code and cross-checked byte-for-byte against `lib/networking/`
  (13 vectors: three volumes, eight source indices, mute, power-on golden
  vector) before the first send.

## Safety envelope (written before the first send)

- Volume commands only at −41.0, −40.5, −40.0 and one −40.25 probe; the
  amp was already at −40.0. Every builder call passed a −35 dB ceiling.
- No power commands at all (no boot experiments were needed).
- Mute toggled only in pairs and restored to off.
- Source commands only among this unit's enabled slots (0–4, 14) plus
  disabled/out-of-range probes; forced −40.0 after every switch, slot 0
  restored at the end of every run.
- Every run asserts the start state (on, slot 0, −40.0, unmuted) and
  aborts otherwise; run 1 aborts if the control trial fails.

## Method

A trial sends the packet(s), then waits up to 1.5 s for a broadcast
**received on `eno1`** and **timestamped after the send** whose decoded
field equals the expected value; the delay to that broadcast is the
reported latency. Volume trials alternate −40.5 / −40.0 so the expected
value always differs from the current one and a stale broadcast cannot
pass as a confirmation. (One exception is called out under E5.)

## Results

### Baseline (30 s passive, no sends)

| Measurement | Value |
|---|---|
| Broadcasts received on `eno1` | 150 in 30 s — **5.0 Hz** |
| Inter-packet gap, `eno1` (min / median / max) | 197 / 200 / 204 ms |
| Same broadcasts received on `wlan0` | 74 — **51 % fewer** |
| Delay of the `wlan0` copy after the wired copy | 8 / 66 / 164 ms |

The earlier "~1 Hz nominal, up to ~5 Hz during state changes" was wrong:
the amp broadcasts at a steady 5 Hz while idle. The Wi-Fi figures are
this desktop's adapter (possibly in power-save; broadcast frames are
held by the AP until the next DTIM beacon) and are **not** a phone
measurement — see TODO.md.

### Run 1 — counters, duplicates, CRC, mute, Wi-Fi

| # | What was sent | Applied | Latency ms (min / med / max) |
|---|---|---|---|
| E0 | Control: app-style double send, contiguous counters from (0,0) | 2 / 2 | 172 / – / 190 |
| E1 | **Single** send, contiguous counters, Ethernet | **20 / 20** | 89 / 96 / 200 |
| E2 | Single send, counters **frozen at (0,0)** every time | 6 / 6 | 91 / 93 / 100 |
| E3 | Single send, counters `FFFF/FFFF`, `1234/9ABC`, decreasing, mismatched, `8000/0000`, `0000/8000` | 6 / 6 | 95 / 97 / 99 |
| E4 | Byte-identical copies ×2 and ×5 (same counters in every copy) | 4 / 4 | 91 / 93 / 94 |
| E5 | **Corrupted CRC**, single ×4 and double ×1 | **0 / 5** | – |
| E5c | Byte 0 = `0x45` instead of `0x44`, CRC recomputed | 0 / 1 | – |
| E5d | Packet **truncated to 14 bytes** (no zero padding), CRC valid | 1 / 1 | 82 |
| E6 | Mute on / off, single send | 4 / 4 | 97 / 99 / 200 |
| E7 | Single send over **Wi-Fi** (`SO_BINDTODEVICE wlan0`) | **18 / 20** | 82 / 95 / 297 |
| E7b | Double send over Wi-Fi | **10 / 10** | 90 / 96 / 100 |

E5 reads "2/4" in the log: the two "OK" lines are the −40.0 trials whose
predicate matched the *unchanged* state after the preceding −40.5 had
been dropped (the `vol=` column never left −40.0). Real result 0/5.

### Run 2, 3, 4 — source-select payloads

Payload bytes are given as the float32 whose top 16 bits they are.

| Probe | Payload | From slot | Result |
|---|---|---|---|
| S1 | `40 60` (3.5) — the table's bytes for index 3 | 0 | → **3** (161 ms) |
| S2 | `FF E0` (NaN) — the table's "−1" for index 0 | 3 | → **0** (94 ms) |
| S3 | `40 40` (3.0) | 0 | → **3** (91 ms) |
| S4 | `00 00` (0.0) | 3 | → **0** (100 ms) |
| S5 | `3F C0` (1.5) | 0 | → **1** — truncation, not rounding |
| S6 | `40 30` (2.75) | 1 | → **2** — truncation, not rounding |
| R7 | `40 90` (4.5) | 0 | → **4** |
| S9 | `41 60` (14.0) — the table's bytes for index 14 | 14 | 14 (no-op, already there) |
| S12 | `BF 80` (−1.0) | 14 | → **0** |
| S7, D09, D09b | `41 10` (9.0) — disabled slot 9, current raw fallback | 2, 0, 3 | → **14** every time (3/3) |
| S8, R5 | `40 A0` (5.0) — disabled slot 5, in the table | 14, 0 | no-op (2/2) |
| D06–D08, D10–D12, R6 | 6.0, 7.0, 8.0, 10.0, 11.0, 12.0, 13.0 — disabled | 0 | no-op (7/7) |
| R1, R2, R3, R4 | 16.0, 29.0, 30.0, 100.0 | 0 | no-op (4/4) |
| S10 | `41 C0` (24.0) — what `0x4000 \| (14 << 5)` gives *without* the `>> 1` | 14 | no-op |
| S11 | `41 80` (16.0) | 14 | no-op |

Forced −40.0 after every switch: applied every time (26/26).

### Volume encoding

`tool/protocol_probe/bf16_check.py`: the sign-flagged `dbConvert` word
equals the top 16 bits of `float32(dB)` on **every** 0.5 dB step from 0
to 100 dB and from 0 to −100 dB (0 mismatches). One live probe: the
word for −40.25 (`C2 21`, representable exactly) was applied as
**−40.5** — the amp quantizes to half steps itself.

## Conclusions

1. **Counters are ignored.** Contiguity, starting value, monotonicity
   and uniqueness all irrelevant; the amp does not de-duplicate either.
   Nothing needs a persisted counter across processes. Keep the two
   counters and the double send for wire fidelity; there is nothing to
   "clean up".
2. **CRC is checked; the magic bytes are checked; the padding is not.**
   A 14-byte packet works. Keep sending 142 bytes anyway — it is what
   every implementation and the original capture used.
3. **One copy suffices on Ethernet; Wi-Fi dropped 1 in 10 single sends
   and 0 in 10 double sends.** Decision: keep the fixed double send, no
   adaptive retry. The confirmation channel (Task 3.1.x) is the real
   recovery path, and a dropped command is visible there.
4. **Confirmation latency is bounded by the 200 ms broadcast period**,
   not by processing: 82–200 ms on the wire, median ~95 ms. Over Wi-Fi
   the broadcast itself arrives up to ~170 ms later still and, on this
   adapter, half the time not at all.
5. **The select-source payload is `float32(index)` truncated to 16 bits,
   and the amp truncates the float toward zero.** NaN and negative
   values select slot 0. The seven-entry table is a set of coincidences
   that happen to land in the right integer ranges; the `>> 1` for
   `cmdValue > 7` happens to reproduce the float encoding for 8–15 and
   nothing else. **Indices 16–29 are unreachable with the current
   encoder** (they encode as 32.0, 36.0, …, no-ops) → Task 1.1.4.
6. **The "raw fallback selects Air" observation was a per-unit alias,
   not a formula artefact:** slot 9 → 14 on this unit from three
   different starting slots; every other disabled or out-of-range index
   is a no-op. A client that only offers indices the broadcast flags as
   enabled can never hit the alias.
7. **The volume word is `bfloat16(dB)`**, which is why the recursion's
   golden vectors look like float literals. Explanation only; the
   literal port and its pinned bytes stay.

## What this run could not settle

- **Unmapped-but-enabled indices** (the actual "raw fallback" case): this
  unit enables only 0–4 and 14, all of which are in the table. The float
  model predicts `bfloat16(index)`; needs a unit with an enabled slot
  ≥ 6 to confirm, ideally ≥ 16.
- Whether the 9 → 14 alias exists on other units.
- Wi-Fi broadcast loss and delay **on the phones** (only the desktop
  adapter was measured).
- Anything about a booting amp — no power commands were sent.
