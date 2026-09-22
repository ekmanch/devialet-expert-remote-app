# Volume / mute / limit-clamp verification on the real amp — 2026-09-22 (Task 3.6.7)

The app on the Galaxy S25 (debug build of this working tree, Android
variant, driven hands-free over wireless adb) against the owner's Expert
Pro 140 at 192.168.0.22. Two logs side by side:

- `docs/captures/2026-09-22-volume-verification.txt` — every raw change
  in the amp's status broadcast on the dev machine's `eno1`
  (`tool/protocol_probe/run6_volume.py watch 200`); 1000 packets in
  200 s, no gap > 250 ms.
- `docs/captures/2026-09-22-volume-verification-app.txt` — the app's
  `[amp]` trace over `adb logcat -s flutter` (`docs/architecture.md`
  §15): `send volume` / `send mute` / `clamp` at the send instant, `rx`
  for the selected amp's broadcasts, `view` for every displayed change.

The two clocks are independent (phone vs dev machine); offsets below are
within one log. The KDE daemon stayed running (it only sends on a boot;
no boot in this run).

**Envelope (written before the first send, checklist 27):** no power
commands; the phone's Settings ceiling set to −25.0 for the run (its
wire-side `maxDb`, so nothing the app sends can exceed −25 dB); gestures
aimed at −50…−30; harness sends only the final restore. Start and end
state: On / slot 0 / −25.0 / unmuted. The ceiling pref was restored to
the owner's −10.0 afterwards.

## Results

| # | Gesture (adb) | App trace | Wire | Verdict |
|---|---|---|---|---|
| A1 | tap VOL + at the ceiling (−25) | nothing | nothing | bound step sends nothing (3.6.2) |
| A2 | tap VOL − ×3 | `view`+`send volume` −26 / −27 / −28, same ms | confirmed +102 / +254 / +200 ms | one tap = one 1 dB step (3.6.0) |
| B | hold VOL − 2000 ms | press step, first repeat **+308 ms**, then every 102–104 ms: 17 sends −29…−45 | raw trails the sends by 1–2 steps during the hold; −45 confirmed +248 ms after the last send | 300/100 schedule on device; **no `view` line ever moved against the gesture** — gotcha #1 absent |
| C | hold VOL + 1000 ms | 7 sends −44…−38 (first repeat +303 ms) | −38 confirmed +187 ms | same |
| D1 | dial 9 → 12 o'clock, 1500 ms | one `send volume −38` on release (no `view`: already −38) | — | release-only send (3.6.4) |
| D2 | dial 12 → 9, 700 ms | one send −46 | confirmed +118 ms | no jerk after release — gotcha #2 absent |
| D3 | dial 9 → 12, 400 ms | one send −38 | confirmed +108 ms | same |
| E1 | tap Mute | `send mute true` | `mute=True` | 3.7.0 |
| E2 | tap VOL + while muted | `send mute false` then `send volume −37`, 2 ms apart; `view muted=false` at once | `mute=False vol=−37` | auto-unmute order = KDE (3.6.5) |
| E3 | Mute, then dial swipe | `send mute false` + `send volume −46` | `mute=False vol=−46` | dial path covered too |
| F1 | Settings: floor + ×5 (−50 → −45; volume −46) | exactly one `clamp from=−46 to=−45` + send, on the 5th tap | −45 confirmed +141 ms | in range = nothing; one command per excluding change (3.6.6) |
| F2 | floor + ×2 (−44, −43) | one clamp each | +251 / +182 ms | both directions covered by the symmetric clamp; floor here, ceiling in the unit tests |
| F3 | floor − ×7 back to −50 | nothing | nothing | widening never sends |
| F4 | Mute; floor + ×8 (−50 → −42; volume −43) | `clamp −43 → −42` + `send volume` only, **no `send mute`**; `view muted=true` throughout | `raw=111 mute=True` | corrections leave the amp muted (3.7.1) |
| F5 | floor back to −50; unmute | `send mute false` | `mute=False` | — |
| G | amp sheet → None; tap VOL +; reselect | `view hasAmp=false`; **nothing** on the tap; reconnect `view −42`, no clamp | nothing | control measurement (checklist 22): the gate, not luck |

Restore: harness slot 0 (94 ms), −25.0 (193 ms), unmuted.

## Timing facts recorded

- Confirmation latency (send → matching `rx`): 81…288 ms across 30 user
  sends (median ≈ 190 ms), bounded by the 200 ms broadcast period as in
  `docs/protocol.md` "Timing facts".
- Hold-to-repeat on the S25: first repeat +303 / +308 ms after the press
  step, then 102–104 ms — the flat 300/100 schedule with one frame of
  slack. The press step itself lands ≈ 100 ms after the touch inside the
  scroll view (`kPressTimeout`, Task 3.6.1's note) — not measurable from
  these logs (different clocks); a hands-on judgement call for the owner.
- During a 2 s hold the amp's broadcast lags the sent value by 1–2 steps
  (one or two 100 ms sends per 200 ms broadcast). The pending mask
  absorbed every one of those 20+ stale reports: the `view` trace is
  strictly monotonic through both holds.

## Not covered here

- The hands-on feel of 300/100 and of dial tracking (checklist 23) —
  owner's call, recorded in TODO 3.6.1 / 3.6.7.
- Ceiling-driven clamps on hardware (the floor was used because the
  volume sat near it; the ceiling direction is unit-tested and uses the
  same symmetric clamp).
- Power cycles (3.6.4b's user-send-inside-the-hold on hardware): the KDE
  daemon was left running and no boot was performed; the rule is
  unit-tested at the pure and owner levels.
