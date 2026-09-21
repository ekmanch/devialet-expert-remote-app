# Boot verification run — 2026-09-21 (Task 3.5.2)

Live run of the **app itself** (debug build on the Galaxy S25, Android UI
variant, over Wi-Fi) against the owner's Expert Pro 140 (`192.168.0.22`,
"My Devialet-ETH", on Ethernet), with a raw UDP capture on the Linux dev
machine next to it. Settles TODO.md Tasks 3.5.0 / 3.5.2 and the S25
re-check that 3.2.5 asked for: the 20 s boot machine, the +500 ms
startup-volume send and the 1500 ms post-boot display hold have now been
observed end-to-end on hardware, not only in unit tests and the simulator.

- Wire log (every raw-byte change after each first On packet, every
  harness send): `docs/captures/2026-09-21-boot-verification.txt`,
  written by `tool/protocol_probe/run5_boot.py`.
- App log (the `[amp]` debug trace over `adb logcat`, Task 3.5.2's tracer):
  `docs/captures/2026-09-21-boot-verification-app.txt`.
- No pcap (no root); the listener is an ordinary UDP socket on 45454
  tagged with the receiving interface, as on 2026-09-19. **The wire log
  cannot see the phone's unicast commands** (port 45455); the app's send
  instants come from the app trace only, and their *effect* (the raw byte
  going 111 → 115) is on the wire.
- Screenshots were taken over adb at each phase; they are described
  below and not committed.

## Safety envelope (written before the first send)

- Power off / on from the harness allowed (owner decision 2026-09-21),
  only in the control boot and the two external-boot trials; every other
  boot was started from the app's own Power button.
- The startup volume is the app's own setting (−40.0, the default).
  Harness volume commands only −35.0 (a pre-shutdown byte that differs
  from both the −40 target and the −42 misreport) and the final −25.0
  restore; every `vol_payload` was built with `maxdb = −25`.
- No mute or source commands except the end-of-run restore to slot 0.
- Every mode asserts the start state (On, slot 0, unmuted) and aborts
  otherwise; "no On within 25 s" aborts without re-sending.
- The KDE widget's daemon (`devialet-remote-daemon.service`) was stopped
  for the whole run — since 2026-09-20 it also sends −40 on an observed
  boot and would have been a second sender — and restarted afterwards.
- The amp was restored to On / slot 0 / −25.0 / unmuted; the phone's
  screen timeout and stay-awake flag were restored.

## Method

The phone was driven hands-free over wireless adb: `adb shell input tap`
on the Power button, `adb exec-out screencap` for screenshots, `adb
logcat -s flutter | grep '[amp]'` for the trace. Each trial powers the
amp Off, dwells ~10 s (a guess, not a measured constant — checklist 14),
powers it On, and follows the raw volume byte for 30 s after the first
On packet on `eno1`.

**Clock alignment:** every offset below is measured from the **first On
packet** — the wire's on the dev machine, the app's on the phone — so the
two logs need no wall-clock synchronisation. Where the app saw its first
raw-111 packet later than the wire (+306 / +409 ms instead of +200), it
had missed one 5 Hz broadcast over Wi-Fi; it never missed a first On
packet (the pre-shutdown byte matched on all five app-observed boots),
so the app's +500 ms clock started on the same packet as the wire's.

## Results

Six boots: one control with the app force-stopped (T0) and five with the
app connected — three started from the app's Power button (A, C, F) and
two from the harness while the app watched (D, E). Pre-shutdown = the
raw byte the amp was powered off at (115 = −40.0 is the 3.2.4 case).

| Trial | Started by | Pre-shutdown | Off→On send→first On | raw 111 (wire / app) | app `startup-send` | raw 115 (wire) | hold released (app) |
|---|---|---|---|---|---|---|---|
| T0 control | harness, **app stopped** | 115 | 15.00 s | +198 / — | — | **never** (111 still at +30 s) | — |
| A | app | 115 (−40) | 16.02 s | +200 / +206 | +594 ms | +800 | +793 ms, confirmed |
| C | app | 125 (−35) | 16.08 s | +200 / +306 | +582 ms | +800 | +784 ms, confirmed |
| D | harness, app watching | 115 | 15.00 s | +199 / +204 | +572 ms | +800 | +776 ms, confirmed |
| E | harness, source sheet open | 115 | 15.00 s | +200 / +208 | +615 ms | +800 | +822 ms, confirmed |
| F | app | 125 (−35) | 15.99 s | +199 / +409 | +555 ms | +799 | +819 ms, confirmed |

Per trial, the wire saw 151 packets in the 30 s after On with no gap
over 250 ms; the amp's Off confirmation after a power-off send was
227–393 ms.

### What the display did (the `view` lines of the app trace)

- On every app-observed boot the displayed volume went to **−40.0 on the
  first On packet** and never changed again: the −42 packet was recorded
  (`rx raw=111`) with **no `view` line**, and the release on raw 115 was
  a no-op for the display. Screenshots at +0.3 s and +1.0 s after On read
  −40.0. The 1500 ms fallback never fired (all five releases
  `reason=confirmed`, at +776…+822 ms).
- **A** is the 3.2.4 regression case on hardware: the first On packet
  already carried the target (115) and the hold was *not* released by it —
  `hold released` came after `boot startup-send`, on the raw-115 packet
  that followed the app's own send. Before the 2026-09-20 fix this was
  the ~300 ms −42 flash.
- **T0** is the control: with nothing sending, raw 111 appeared at
  +198 ms and was still the value 30 s later — the capture sees the bug,
  and no other client on the LAN corrects it.

### 3.5.0 — presentation through a real boot (screenshots, Android variant)

- Off, connected: hollow status dot, "192.168.0.22 · Connected",
  "Power On"; dial / VOL / Mute / Source dimmed with the last-known value
  still readable.
- After the Power tap: "Powering on…" with the ring spinner and amber
  border, card subtitle "Booting…", pulsing amber dot; every other
  control stays dimmed for the whole ~16 s. A second tap while Booting
  produced **no** `send power` line (trial A).
- First On: "Power Off", copper dot, everything un-dims together, dial
  −40.0 at once.
- External boots (D, E): the app showed the plain Off presentation while
  the amp was booting — no spinner, no "Booting…" — and flipped to On
  when the amp said so (the accepted limitation recorded in TODO.md).

### 3.5.1 — the live source-sheet gate (trial E)

With the source sheet open, the harness powered the amp off: the rows
dimmed to 0.4 in place, a tap on "AirPlay" while Off did nothing (sheet
still open, "Optical 1" still checked, no `view` change, nothing sent),
and the rows came back live on the first On packet. Sheet glyphs
(◉ ◫ ◍ ◈ ◐ ◇ ✓) all rendered, no tofu.

## Conclusions

1. **The startup send lands at +555…+615 ms** after the app's first On
   packet (design: ≥ +500 ms, evaluated at 5 Hz) and the amp applies it
   by the +800 ms broadcast every time (5/5) — comfortably past the
   latest amp-side application ever observed (+394 ms, gotcha #9).
2. **The post-boot hold works on the real misreport**: −42 was recorded
   on every boot and displayed on none; the first On packet's
   pre-shutdown byte (equal to the target in 3 of 5 boots) never released
   the hold early (gotcha #8 watch-out #2).
3. **Observed external boots get the same correction** (3.2.5): 2/2 from
   another client, with the KDE daemon stopped so the app was provably
   the sender.
4. **Boot time**: 15.00 s ×3 when the harness sent power-on, 15.99–16.08 s
   ×3 when the app did. Both inside the documented 15.0–18.6 s spread and
   well under the 20 s timeout; the ~1 s difference is not explained (the
   phone is on Wi-Fi and its Off dwell was ~0.5 s longer) and was not
   investigated.
5. **Wi-Fi on the S25** dropped a 5 Hz broadcast twice in six 30 s
   windows (the +200 ms packet in C and F); the app never went "Not
   connected" and never missed a first On packet.

## What this run could not settle

- The 1500 ms fallback path on hardware (it never had to fire); it stays
  covered by the owner tests only.
- A user re-target inside the hold (3.6.4b): user volume sends are still
  display-only until Task 3.6.x.
- The iOS variant: same code path, but no iOS device was involved.
- Why an app-initiated boot reads ~1 s longer than a harness-initiated
  one.
