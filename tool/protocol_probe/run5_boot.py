"""RUN 5 — boot / startup-volume / post-boot-hold verification (Task 3.5.2).

    python3 run5_boot.py <log> <mode>      (SHOTS=<dir> to grab adb screenshots)

Modes (compose one trial each; the app on the phone is the thing under test):
  t0       control: harness power off -> 10 s -> on, app force-stopped; the raw
           -42 (byte 111) must persist for 30 s — proves the capture sees the bug
  watch    no sends: wait for an Off then an On the *app* causes (T1/T2/T4)
  t3       harness power off -> 10 s -> on while the app watches (external boot)
  set35 / set40   volume to -35 / -40 (a pre-shutdown byte distinguishable from
           -40 / the -42 misreport, or the 3.2.4 case)
  restore  slot 0, unmute, -25.0 — the owner's pre-run state

The 10 s Off dwell is a guess, not a measured constant (checklist item 14).
Every offset is from the FIRST ON packet on eno1; the app trace uses its
own first On packet — no wall-clock sync between the two logs.
"""
from harness import *
import os, subprocess, threading

MODE = sys.argv[2] if len(sys.argv) > 2 else "watch"
SHOTS = os.environ.get("SHOTS")
log(f"=== RUN 5 {MODE}: boot / startup-volume / post-boot hold (Task 3.5.2) ===")
log("ENVELOPE: power on/off allowed (owner decision 2026-09-21); startup volume is the app's own (-40.0, its default); "
    "harness volume only in -50..-35 plus the single -25.0 restore, every vol_payload passes maxdb=-25; "
    "mute only restored off; source only restored to slot 0; end state On / slot 0 / -25.0 / unmuted")
time.sleep(1.2); st = L.latest()
assert st and st[2] and not st[4] and st[3] == 0, f"unexpected start state {st} (need On, slot 0, unmuted)"
log(f"start state: power={st[2]} src={st[3]} mute={st[4]} vol={st[5]:+.1f} raw={st[6]}")

pc = cc = 0
def dbl(payload):
    global pc, cc
    a = packet(pc, cc, *payload); pc += 1; cc += 1
    b = packet(pc, cc, *payload); pc += 1; cc += 1
    return [a, b]
V = lambda db: (lambda e: e[5] == db)
def vol(db):
    assert db == -25.0 or -50.0 <= db <= -35.0, f"volume {db} is outside the envelope"
    return dbl(vol_payload(db, -25.0))
def power(on):
    t = send(dbl(POWER_ON if on else POWER_OFF)); log(f"SEND power {'on' if on else 'off'}"); return t

def wait_first(pred, t_from, timeout, what):
    deadline = time.monotonic() - T0 + timeout
    while time.monotonic() - T0 < deadline:
        for e in L.since(t_from, "eno1"):
            if pred(e): return e
        time.sleep(0.01)
    log(f"ABORT: no {what} within {timeout:.0f} s"); sys.exit(2)

def screenshot(tag, t_on, delay):
    def run():
        while time.monotonic() - T0 < t_on + delay: time.sleep(0.005)
        t_call = time.monotonic() - T0
        path = os.path.join(SHOTS, f"{MODE}-{tag}-{int(delay*1000)}ms.png")
        with open(path, "wb") as f:
            subprocess.run(["adb", "exec-out", "screencap", "-p"], stdout=f, check=False)
        log(f"  screenshot {path} requested at +{(t_call - t_on)*1000:.0f} ms, done at +{(time.monotonic()-T0-t_on)*1000:.0f} ms")
    threading.Thread(target=run, daemon=True).start()

def follow(t_off_ev, t_on_ev, follow_s=30.0, shots=False):
    """Logs every raw change for follow_s after the first On packet; returns the summary dict."""
    t_on = t_on_ev[0]
    pre = [e for e in L.since(t_off_ev[0] - 5, "eno1") if e[0] < t_off_ev[0]]
    log(f"FIRST OFF at {t_off_ev[0]:.3f}  (pre-shutdown raw={pre[-1][6] if pre else '?'} vol={pre[-1][5] if pre else '?'})")
    log(f"FIRST ON  at {t_on:.3f}  raw={t_on_ev[6]} vol={t_on_ev[5]:+.1f}  boot Off->On {(t_on - t_off_ev[0])*1000:.0f} ms")
    if shots and SHOTS:
        screenshot("on", t_on, 0.3); screenshot("on", t_on, 1.0)
    prev = t_on_ev[6]; first = {}; seen_t = t_on
    while time.monotonic() - T0 < t_on + follow_s:
        for e in L.since(seen_t + 1e-6, "eno1"):
            seen_t = e[0]
            if e[6] != prev:
                log(f"  +{(e[0]-t_on)*1000:6.0f} ms raw={e[6]} vol={e[5]:+.1f} power={'on' if e[2] else 'off'}")
                first.setdefault(e[6], (e[0]-t_on)*1000); prev = e[6]
        time.sleep(0.02)
    ev = L.since(t_on, "eno1")
    gaps = [round((b[0]-a[0])*1000) for a, b in zip(ev, ev[1:])]
    at = lambda s: next((e[6] for e in ev if e[0] >= t_on + s), None)
    fmt = lambda raw: f"{first[raw]:.0f} ms" if raw in first else "never"
    log(f"SUMMARY {MODE}: first Off -> first On {((t_on - t_off_ev[0])*1000):.0f} ms (includes the Off dwell); "
        f"first raw111 at {fmt(111)}; first raw115 at {fmt(115)}; raw@5s={at(5)} raw@29s={at(29)}; "
        f"eno1 packets={len(ev)}; gaps>250ms={sum(g>250 for g in gaps)}")
    return first

def harness_boot(shots):
    t = power(False); off = wait_first(lambda e: not e[2], t, 10, "Off")
    log(f"  Off confirmed {(off[0]-t)*1000:.0f} ms after the send; dwelling 10 s (a guess, checklist 14)")
    time.sleep(10)
    t = power(True); on = wait_first(lambda e: e[2], t, 25, "On")
    log(f"  On confirmed {(on[0]-t)*1000:.0f} ms after the send")
    return follow(off, on, shots=shots)

if MODE == "t0":
    log("T0 control: the app must be force-stopped (adb shell am force-stop com.ekmanch.devialet_expert_remote_app)")
    first = harness_boot(shots=False)
    log("T0 verdict: " + ("raw 111 persisted with nothing correcting it" if 115 not in first else "raw 115 appeared — another sender is on the LAN, ABORT the run"))
elif MODE == "watch":
    log("watch: waiting for the app to power the amp Off, then On (tap now)")
    off = wait_first(lambda e: not e[2], time.monotonic() - T0, 180, "Off")
    on = wait_first(lambda e: e[2], off[0], 60, "On")
    follow(off, on, shots=True)
elif MODE == "t3":
    log("T3 external boot: the app must be in the foreground and connected")
    harness_boot(shots=True)
elif MODE in ("set35", "set40"):
    db = -35.0 if MODE == "set35" else -40.0
    trial(f"volume {db} (double send, maxdb -25)", vol(db), V(db), timeout=2.0)
elif MODE == "restore":
    t = send(dbl((0x00, 0x05, 0x00, 0x00))); lat = wait_for(lambda e: e[3] == 0, t, 2.0); log(f"restore slot 0 via 0x0000 -> {lat} ms")
    time.sleep(0.2)
    if L.latest()[4]: trial("unmute", dbl(MUTE_OFF), lambda e: not e[4], timeout=2.0); time.sleep(0.2)
    trial("volume -25.0 (final restore, double send)", vol(-25.0), V(-25.0), timeout=2.0)
else:
    log(f"unknown mode {MODE}"); sys.exit(1)
log("final state", L.latest())
