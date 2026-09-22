"""RUN 6 — user volume / mute / limit-clamp verification (Task 3.6.7).

    python3 run6_volume.py <log> watch <seconds>     raw timeline while the app is driven
    python3 run6_volume.py <log> restore             slot 0, unmute, -25.0

The app on the Galaxy S25 is the thing under test; this script only *listens*
(every raw change on eno1, with mute and source) and restores at the end. The
app's own send instants come from its `[amp]` trace over `adb logcat -s
flutter` (docs/architecture.md §15); the two logs line up by wall clock
(both print an absolute timestamp on their first line).

ENVELOPE (written before the first send, checklist 27):
  - no power commands; the KDE daemon may stay running (it only sends on a boot);
  - the phone's Settings ceiling is set to -25.0 for the run (its wire-side
    `maxDb`), so nothing the app sends can exceed -25 dB; gestures aim -50..-30;
  - harness sends: only the final restore (-25.0, unmute, slot 0);
  - end state: On / slot 0 / -25.0 / unmuted (the owner's pre-run state 2026-09-22).
"""
from harness import *
import datetime

MODE = sys.argv[2] if len(sys.argv) > 2 else "watch"
log(f"=== RUN 6 {MODE}: user volume / mute / clamp (Task 3.6.7) wall={datetime.datetime.now().isoformat(timespec='milliseconds')} ===")
log("ENVELOPE: no power commands; phone ceiling -25.0 for the run; harness sends only the final restore "
    "(-25.0 / unmute / slot 0); gestures aim -50..-30")
time.sleep(1.2); st = L.latest()
assert st and st[2] and st[3] == 0, f"unexpected start state {st} (need On, slot 0)"
log(f"start state: power={st[2]} src={st[3]} mute={st[4]} vol={st[5]:+.1f} raw={st[6]}")

pc = cc = 0
def dbl(payload):
    global pc, cc
    a = packet(pc, cc, *payload); pc += 1; cc += 1
    b = packet(pc, cc, *payload); pc += 1; cc += 1
    return [a, b]

if MODE == "watch":
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 60.0
    log(f"watch: logging every raw/mute/source change on eno1 for {secs:.0f} s — drive the app now")
    t_start = time.monotonic() - T0
    prev = None; seen_t = t_start; n = 0
    while time.monotonic() - T0 < t_start + secs:
        for e in L.since(seen_t + 1e-6, "eno1"):
            seen_t = e[0]; n += 1
            key = (e[6], e[4], e[3], e[2])
            if key != prev:
                log(f"  wall={datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]} raw={e[6]} vol={e[5]:+.1f} "
                    f"mute={e[4]} src={e[3]} power={'on' if e[2] else 'off'}")
                prev = key
        time.sleep(0.02)
    ev = L.since(t_start, "eno1")
    gaps = [round((b[0]-a[0])*1000) for a, b in zip(ev, ev[1:])]
    log(f"SUMMARY watch: packets={len(ev)} gaps>250ms={sum(g>250 for g in gaps)} final raw={ev[-1][6] if ev else '?'} "
        f"vol={ev[-1][5] if ev else '?'} mute={ev[-1][4] if ev else '?'}")
elif MODE == "restore":
    t = send(dbl((0x00, 0x05, 0x00, 0x00))); lat = wait_for(lambda e: e[3] == 0, t, 2.0); log(f"restore slot 0 via 0x0000 -> {lat} ms")
    time.sleep(0.2)
    if L.latest()[4]: trial("unmute", dbl(MUTE_OFF), lambda e: not e[4], timeout=2.0); time.sleep(0.2)
    trial("volume -25.0 (final restore, double send, maxdb -25)", dbl(vol_payload(-25.0, -25.0)), lambda e: e[5] == -25.0, timeout=2.0)
else:
    log(f"unknown mode {MODE}"); sys.exit(1)
log("final state", L.latest())
