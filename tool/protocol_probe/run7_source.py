"""RUN 7 — source switch + forced post-switch volume verification (Task 3.8.4).

    python3 run7_source.py <log> watch <seconds>     raw timeline while the app is driven
    python3 run7_source.py <log> restore <db>        slot 0, unmute, the pre-run volume

The app on the Galaxy S25 is the thing under test; this script only *listens*
(every raw / mute / source / power change on eno1, wall-clocked) and restores
at the end. The app's own send instants come from its `[amp]` trace over
`adb logcat -s flutter` (docs/architecture.md §15: `send source`, `rx source=`,
`view source=`, `sheet kind=`); the two logs line up by wall clock (both print
an absolute timestamp on their first line).

ENVELOPE (written before the first send, checklist 27):
  - no power commands; the KDE daemon may stay running (it only sends on a boot);
  - the app selects only slots the broadcast flags enabled on this unit
    (0-4 and 14) — never 9 (the firmware alias) or anything >= 16;
  - the forced post-switch volume is the phone's startup setting (-40.0),
    inside -50..-35; the phone's Settings ceiling is pinned to -25.0 for the
    run (its wire-side `maxDb`), so nothing the app sends can exceed -25 dB;
  - harness sends: only the final restore (slot 0, unmute, the pre-run volume
    given on the command line — -38.0 on 2026-09-24);
  - end state: On / slot 0 / the pre-run volume / unmuted.
"""
from harness import *
import datetime

MODE = sys.argv[2] if len(sys.argv) > 2 else "watch"
log(f"=== RUN 7 {MODE}: source switch + forced volume (Task 3.8.4) wall={datetime.datetime.now().isoformat(timespec='milliseconds')} ===")
log("ENVELOPE: no power commands; enabled slots only (0-4, 14); phone ceiling -25.0 and startup -40.0 for the run; "
    "harness sends only the final restore (slot 0 / unmute / pre-run volume)")
time.sleep(1.2); st = L.latest()
assert st and st[2], f"unexpected start state {st} (need On)"
log(f"start state: power={st[2]} src={st[3]} mute={st[4]} vol={st[5]:+.1f} raw={st[6]}")

pc = cc = 0
def dbl(payload):
    global pc, cc
    a = packet(pc, cc, *payload); pc += 1; cc += 1
    b = packet(pc, cc, *payload); pc += 1; cc += 1
    return [a, b]

if MODE == "watch":
    secs = float(sys.argv[3]) if len(sys.argv) > 3 else 60.0
    log(f"watch: logging every raw/mute/source/power change on eno1 for {secs:.0f} s — drive the app now")
    t_start = time.monotonic() - T0
    prev = None; seen_t = t_start
    while time.monotonic() - T0 < t_start + secs:
        for e in L.since(seen_t + 1e-6, "eno1"):
            seen_t = e[0]
            key = (e[6], e[4], e[3], e[2])
            if key != prev:
                log(f"  wall={datetime.datetime.now().strftime('%H:%M:%S.%f')[:-3]} raw={e[6]} vol={e[5]:+.1f} "
                    f"mute={e[4]} src={e[3]} power={'on' if e[2] else 'off'}")
                prev = key
        time.sleep(0.02)
    ev = L.since(t_start, "eno1")
    gaps = [round((b[0]-a[0])*1000) for a, b in zip(ev, ev[1:])]
    log(f"SUMMARY watch: packets={len(ev)} gaps>250ms={sum(g>250 for g in gaps)} final src={ev[-1][3] if ev else '?'} "
        f"raw={ev[-1][6] if ev else '?'} vol={ev[-1][5] if ev else '?'} mute={ev[-1][4] if ev else '?'}")
elif MODE == "restore":
    target = float(sys.argv[3]) if len(sys.argv) > 3 else -38.0
    assert -50.0 <= target <= -25.0, f"restore volume {target} outside the envelope"
    if L.latest()[3] != 0:
        t = send(dbl(src_payload(0))); lat = wait_for(lambda e: e[3] == 0, t, 2.0); log(f"restore slot 0 via {src_payload(0)[2:]} -> {lat} ms")
        time.sleep(0.2)
    if L.latest()[4]: trial("unmute", dbl(MUTE_OFF), lambda e: not e[4], timeout=2.0); time.sleep(0.2)
    trial(f"volume {target} (final restore, double send, maxdb -25)", dbl(vol_payload(target, -25.0)), lambda e: e[5] == target, timeout=2.0)
else:
    log(f"unknown mode {MODE}"); sys.exit(1)
log("final state", L.latest())
