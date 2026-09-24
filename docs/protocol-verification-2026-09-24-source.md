# Source switch + forced volume verification on the real amp — 2026-09-24 (Task 3.8.4)

The app on the Galaxy S25 (debug build of this working tree, Android
variant, driven hands-free over wireless adb with
`tool/protocol_probe/run7_gestures.sh`) against the owner's Expert Pro 140
at 192.168.0.22. Three logs:

- `docs/captures/2026-09-24-source-verification.txt` — every change of
  raw volume / mute / source / power in the amp's status broadcast on the
  dev machine's `eno1` (`tool/protocol_probe/run7_source.py watch 95`);
  475 packets in 95 s, no gap > 250 ms.
- `docs/captures/2026-09-24-source-verification-app.txt` — the app's
  `[amp]` trace over `adb logcat -v time -s flutter`
  (`docs/architecture.md` §15): `send source` / `send volume` /
  `send mute` at the send instant, `rx` for the selected amp's broadcasts
  (now with `source=`), `view` for every displayed change (now with
  `source=`), `sheet kind=` for the owner's sheet slot.
- `docs/captures/2026-09-24-source-verification-mute.txt` — a harness-only
  follow-up (`run7b`, script kept in the session scratchpad only; its
  envelope is in the log's first lines) isolating the mute finding below.

Both device clocks print wall time (the phone's logcat, the harness's
`wall=`); they agreed to within the 200 ms broadcast period, so the
offsets below are read within one log. The KDE daemon stayed running (it
only sends on a boot; no boot in this run).

**Envelope (written before the first send, checklist 27):** no power
commands; the app selects only slots the broadcast flags enabled on this
unit (0–4 and 14) — never 9 (the firmware alias) or anything ≥ 16; the
forced post-switch volume is the phone's startup setting (−40.0), inside
−50..−35; the phone's Settings ceiling pinned to −25.0 for the run (its
wire-side `maxDb`, edited in `shared_prefs` via `run-as` with the app
force-stopped, restored to −10.0 afterwards); harness sends only the
final restore, extended for the follow-up to mute on/off and two source
switches (0 and 1) with the same forced −40. Start state On / slot 0 /
−38.0 / unmuted; end state the same. Screen kept on with
`svc power stayon true`, restored (checklist 30).

**Tap points on the S25 (1080 × 2340), measured by screencap:** source
card (540, 2080); sheet rows Optical 1 (540, 1175), UPnP (540, 1370),
Roon Ready (540, 1564), AirPlay (540, 1760), Spotify (540, 1955), AIR
(540, 2149); the scrim above the sheet (540, 400). VOL − (292, 1603) and
Mute (331, 1829) as before.

## Results

| # | Gesture (adb) | App trace | Wire | Verdict |
|---|---|---|---|---|
| D1 | back key on the sheet left open from the screenshot | `sheet kind=none` | nothing | dismissal writes back (3.8.2) |
| S1 | tap source card | `sheet kind=source` | nothing | — |
| S2 | row UPnP (1) | `view source=1 db=−40.0` and `send source index=1 db=−40.0 ceiling=−25.0` in the **same ms**, `sheet kind=none` +5 ms, `rx source=1 raw=115` +89 ms | one packet: `src=1 raw=115` (was 119) | switch **and** forced volume land together; both slots armed in one write (3.8.0 / 3.8.1) |
| S3–S6 | Roon Ready (2), AirPlay (3), Spotify (4), AIR (14) | one `send source` each; confirmed +85 / +73 / +67 / +50 ms | `src=2/3/4/14`, `raw=115` each | every enabled slot incl. 14 reaches the amp |
| S6b | Optical 1 (0) | `send source index=0`; confirmed +24 ms | `src=0` | the pinned `FF E0` (NaN) selects slot 0 |
| S7 | VOL − ×5, then UPnP (1) | five `send volume` −41…−45 (each confirmed 63…367 ms); then `send source index=1 db=−40.0`, `view db=−40.0` at once, confirmed +155 ms | raw 113 → 105, then **one packet `src=1 raw=115`** | **the forced volume does its job**: −45 → −40 on the switch (gotcha #5) |
| S8 | Mute on UPnP, then Roon Ready (2), then Mute again | `send mute muted=true`, `view muted=true`, then `view muted=false` at **+460 ms** (mask expired, no confirmation); switch: `send source`, **no `send mute`**; second Mute: same, rolled back +550 ms | **`mute=True` never appears**; `src=2 raw=115` +37 ms | a switch never touches mute (3.7.1) ✔ on the app side; the mute itself is a **test artefact** — nothing was playing on UPnP / Roon Ready and the amp does not mute silence (owner, same day), see below |
| S9 | AirPlay (3), reopen, Spotify (4) — 0.9 s apart | two `send source`, `view` moved with each tap, both confirmed (+90 / +169 ms) | `src=3` then `src=4` | no jerk; the 400 ms rapid-repeat case could not be produced by adb (the sheet's open animation is in the way) |
| D2 | open, drag the sheet down | `sheet kind=source` → `kind=none` +1.9 s, **no `send`** | nothing | control measurement (checklist 22) |
| D3 | open, tap the scrim | `kind=none` +1.6 s, no `send` | nothing | same |
| D4 | open, edge swipe (predictive back) | `kind=none` +1.9 s, no `send` | nothing | same |
| R | Optical 1 (0) | `send source index=0`; confirmed +256 ms | `src=0 raw=115` | — |

Restore: harness volume −38.0 (95 ms) at the end of the follow-up; slot 0
and unmuted were already the state.

**Every `view` line moved with the gesture and never against it**: no
stale broadcast leaked through the source mask or the volume mask across
11 switches (gotchas #1/#2 absent). Every dismissal path exercised on the
device wrote `none` back (D1 back key, D2 drag-down, D3 scrim, D4
predictive back, and the row pop on every S row).

## Mute needs a signal — harness follow-up (run7b), a test artefact

| Step | Harness send | Result |
|---|---|---|
| A | mute on / off on slot 0 (Optical 1) | applied, +44 / +193 ms |
| — | switch to slot 1 + forced −40 (as the app sends) | applied +190 ms |
| B | mute on, 4 s after the switch; repeated 3 s later | **NOT APPLIED, twice** — `mute=False` throughout |
| — | switch back to slot 0 + forced −40 | applied +383 ms |
| C | mute on / off on slot 0, 2 s after switching back | applied, +199 / +197 ms |

This first read as "the amp ignores mute on network inputs", which was
wrong (owner correction, same evening): nothing was streaming on UPnP or
Roon Ready, and **the amp does not mute a signal that is not playing**
— the status bit simply never changes. Optical 1 carries the TV/PC feed,
which is why mute works there instantly. So run7b measured the test
setup, not the amp: a mute check has to be done on an input with audio
(Optical 1, or Roon with music started by the owner — TODO 3.8.7). The
app-side observation stands and is the useful part: the Mute button
showed Muted for the 400 ms mask and then followed the amp back to
unmuted, because the mask only trusts a confirmation (checklist 25);
the mute button is not wrong, the input was silent.

## Timing facts recorded

- Confirmation latency for a source switch (`send source` → `rx source=`):
  24…257 ms across 11 switches (median ≈ 85 ms), and the forced volume
  was in the **same** confirming packet every time — no settling gap
  between the two pairs, as `docs/protocol.md` records (★ 6/6, now
  17/17 with this run).
- The sheet's route completes 1.6…1.9 s after an adb dismissal gesture
  (Material sheet animation + the gesture script's own sleeps), with no
  send in between.
- Source and forced volume arrive in one broadcast on this unit (11/11);
  the owner still resolves the two slots independently (checklist 12).

## Not covered here

- The power-edge auto-close on hardware (out of envelope: no power
  commands): unit-tested for Off and Booting in `sheets_test.dart`.
- Slots ≥ 6 (none enabled on this unit) and the 4-bit status field's
  inability to confirm slots ≥ 16: encoder cross-checked Dart vs Python
  for 16 and 29 (`xcheck.dart` / `proto.py`), unconfirmable live.
- The iOS device; the 400 ms rapid-repeat switch (needs a finger, TODO
  3.8.6); the amp-sheet "None → tap a row position" control from the
  2026-09-22 run (unchanged code path, not repeated).
- Mute on a network input with music actually playing (Roon; needs the
  owner to start playback) — TODO 3.8.7.
