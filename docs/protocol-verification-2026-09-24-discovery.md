# Discovery, selection and mDNS verification — 2026-09-24 (Task 3.9.6)

Scope: Task 3.9.x on the Galaxy S25 (SM-S931B, wireless adb) against the
owner's Expert Pro 140 at 192.168.0.22, with the dev machine's Avahi as
the raw cross-check (checklist 22). Envelope (checklist 27): selection and
mDNS only — **no power, volume, mute or source command was sent**; the
KDE daemon stayed up. Captures:
`docs/captures/2026-09-24-discovery-verification.txt` (dev machine),
`docs/captures/2026-09-24-discovery-verification-app.txt` (the app's
`[amp]` trace, `adb logcat -v time -s flutter`).

The run is split by who holds the phone: the S25 is on *wireless* adb,
so every step that touches the phone's Wi-Fi is an **owner hand-run**
whose trace is pulled from the logcat ring buffer afterwards
(`adb logcat -G 4M` was set beforehand). Those are listed in §6 and are
**not done yet**.

## 1. Control (dev machine, before any phone run)

`avahi-browse -rtp _spotify-connect._tcp` (wlan0 and eno1):

```
instance  My Devialet
SRV host  Expert140Pro-K48A00904ZE1V.local
A         192.168.0.22   port 80   TXT CPath=/spotifyconnect/zeroconf
```

`avahi-resolve -n Expert140Pro-K48A00904ZE1V.local` → `192.168.0.22`.
The **SRV host** carries the model; the instance name is the friendly
name. `parseModelName` of that host → "Devialet Expert 140 Pro".

## 2. Cold launches — first broadcast → model name (checklist 14)

Debug build, real amp persisted as the selection, app killed and
relaunched via `am force-stop` / `am start` (checklist 21: a real
restart, not a hot reload). Times are the owner's monotonic clock in ms
since the owner built (the `[amp]` prefix).

| launch | session open | first `rx` | `mdns hit` | `mdns applied` | applied − rx | applied − open |
|---|---|---|---|---|---|---|
| 1 | 5 | 171 | 288 | 290 | **119** | 285 |
| 2 | 5 | 159 | 303 | 305 | **146** | 300 |
| 3 | 5 | 158 | 313 | 315 | **157** | 310 |
| 4 | 5 | 208 | 270 | 271 | **63** | 266 |
| 5 | 5 | 158 | 310 | 311 | **153** | 306 |

Median applied − rx **146 ms** (min 63, max 157); applied − session open
266…310 ms. Every launch resolved **inside the first query cycle** and the
session closed `reason=resolved` 1 ms after the apply, so
`kMdnsQueryInterval` (2 s) and `kMdnsLookupWindow` (1 s) never came into
play on the happy path — they only pace the failure path, and stay as
set. `kMdnsSessionBudget` (60 s) was not reached in any run. The KDE
widget's "< 0.6 s from browse start" reference is matched (≈ 0.3 s here).
An earlier warm-up launch measured the same (rx 217, applied 351).

On screen (23:31): the card read "Devialet Expert 140 Pro / 192.168.0.22
· Connected"; the sheet row "Devialet Expert 140 Pro / My Devialet-ETH ·
192.168.0.22" with the check — the mockup's `model` title and `name · ip`
subtitle.

## 3. Manual IP (3.9.3) and the waiting presentation (3.9.0 / 3.9.4)

Sheet → "Enter IP Manually" → `192.0.2.9` (TEST-NET-1, cannot be a real
device) → Connect. Trace: `view power=off db=null muted=false
hasAmp=false source=null` then `sheet kind=none`. On screen: the card
"192.0.2.9 / Connecting…" (the status word in the accent colour, the
pulsing accent ring), the dial "—" with no arc, every control dimmed
and inert; the reopened sheet lists the real amp online and, under
"NOT RESPONDING", the row "192.0.2.9 [MANUAL] / Connecting…" with the
check — "None" unchecked (the 3.0.8 caveat closed). No `mdns session
open reason=new-ip`: a typed IP is not *heard*, so it opens nothing.

## 4. Restart with the typed IP persisted; trust gate live

Killed and relaunched with 192.0.2.9 still selected while the dev
machine advertised a **fake** `_spotify-connect._tcp` service
(`avahi-publish -s "Fake Connect" … 80 CPath=/x`, host `ekmanch-3.local`,
A 192.168.0.134 / .152):

- The selection restored as "192.0.2.9 / Connecting…" and the sheet row
  came back **untagged** (a restored IP is not "typed here" — the
  decision recorded in TODO 3.9.3).
- The real amp resolved as usual (hit 312, applied 315, close 316) even
  though it was not the selection: names are per amp, not per selection.
- Six further launches with the fake advertised (`gate1…6` in the app
  capture). In three of them the fake answered first:
  `mdns hit host=ekmanch-3.local ip=192.168.0.134 known=false` — **never
  followed by an `mdns applied` for that IP** and never listed as an amp;
  the real amp's hit followed within 0…26 ms and was applied. In the
  other three the real amp's hit closed the session before the fake's
  SRV/A chain ran (the cycle stops at cancel), which is the bounded
  behaviour intended. The trust gate holds on the wire, not only in the
  unit tests.

## 5. Real amp re-selected; release build

- Tapping the real amp's row: `view … hasAmp=true`, `sheet kind=none`.
  Relaunch: rx 155, hit 263, applied 264, close 265 — the persisted
  selection reconnects with no tap and the name is resolved again (it
  is never persisted; ~110 ms after the first packet).
- **Release build** (`flutter build apk --release`, signed with the debug
  key per the template, installed over the debug build with the data
  intact): the card showed "Devialet Expert 140 Pro / 192.168.0.22 ·
  Connected" and the sheet the resolved row. This is the **first release
  build with a working socket at all**: the main manifest had no
  `INTERNET` permission until 3.9.5 (only the debug/profile manifests
  carried the template's). No `[amp]` lines in release, as designed.
- The debug build was reinstalled afterwards for the hand-runs below.

## 6. Owner hand-runs — pending (checklist 23; Wi-Fi toggles)

Before each: note the wall clock; the app is the debug build with the
real amp selected. Afterwards: re-find the phone (`avahi-browse -rtp
_adb-tls-connect._tcp` → `adb connect <ip>:<port>`) and pull
`adb logcat -d -v time -s flutter | grep '\[amp\]'` into the app capture.

- [ ] **(a) Silent-amp round trip.** Wi-Fi off on the phone → within 8 s
      the card should read "Reconnecting… · 192.168.0.22" with the
      pulsing ring and the dial "—"; open the sheet: the amp under
      "NOT RESPONDING", still checked, "192.168.0.22 · Reconnecting…",
      "None" unchecked. Wi-Fi on → reconnects without a tap; the model
      name is still there (never cleared). Expect in the trace: `view …
      hasAmp=false`, later `rx` + `view … hasAmp=true`, and **no** new
      `mdns session open` (the name is settled).
- [ ] **(b) Failure path.** Launch with Wi-Fi off, wait ~10 s, turn it
      on. Expect at most one `mdns unavailable error=…` (the 5353 bind
      or the multicast join with no interface), the sheet's row "· name
      unresolved" meanwhile, then the first broadcast → `mdns session
      open reason=new-ip` → hit → applied.
- [ ] **(c) Power-save.** Screen off for 2 min with the app in the
      foreground, then unlock and cold-launch: the same ≈ 0.3 s resolve
      is expected. Then the **control run**: the same with the lock
      short-circuited (`AndroidMulticastLock.acquire` returning without
      the channel call — a temporary patch, reverted) to see whether the
      Samsung radio drops the multicast answer without it (checklist
      20/22: proves the lock is load-bearing, or shows it is not needed
      on this unit). Record either outcome.
- [ ] **3.9.7** hands-on feel (see TODO).

## 7. Checklist pass (items that needed a concrete reason)

- **4** `manualIp` is transient presentation state, not a persisted
  sentinel; the two-state selection is untouched (counter-checked: the
  store never sees a manual key).
- **5** no amp → `volumeDb == null`; the dial takes `double?` and rests
  at its start — there is no sentinel left to clamp.
- **14** the three mDNS constants: measured above; the happy path never
  reaches them, so they stay at 2 s / 1 s / 60 s as failure-path pacing.
- **16** the waiting ring's leg is 900 ms (half the mockup's declared
  1.8 s cycle); the card's status line is one fixed-height line.
- **17** the missing `INTERNET` permission would have read as "every
  command failing uniformly" on the first release build — found by the
  manifest audit, fixed before it bit.
- **19** every harness overrides the model-name source with a fake;
  nothing binds 5353 under `flutter test`.
- **20** counter-runs: Part A (two) and Part B (six) in
  `docs/architecture.md` §12, each red on the intended test; the dot
  pulse test also caught a real bug during development (a running
  controller ignores a `duration` change).
- **22** Avahi on the dev machine as the raw source next to the app's
  trace; a control measurement of something the change cannot affect:
  the `rx` timing (155…217 ms after build) is unchanged from the 3.8.4 run.
- **23** §6 above, pending.
- **26** a source that cannot run leaves "· name unresolved" and traces
  once; the fake service was never shown as an amp.
- **28** trust gate and "resolved once" in `setModelName`; the
  resolver's own gate does the replay's job (C4 counter-run).
- **29** "one continuous browse" vs the one-shot package → cycles.
- **30** no `AppLifecycleState` policy yet (TODO 4.1.0).

Android tablet: emulator / resizable window only, not exercised in this
run. iOS: the Bonjour source and the plist keys are **unverified** until
the iPad session (TODO 4.0.0).
