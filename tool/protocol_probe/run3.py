from harness import *
log("=== RUN 3: disabled/out-of-range index rule, all from slot 0 ===")
log("ENVELOPE: source payloads only, forced -40.0 after every switch, restore slot 0; no power cmds")
time.sleep(1); st = L.latest(); assert st and st[2] and not st[4] and st[5] == -40.0 and st[3] == 0, f"unexpected start state {st}"
pc = cc = 0
def dbl(payload):
    global pc, cc
    a = packet(pc, cc, *payload); pc+=1; cc+=1
    b = packet(pc, cc, *payload); pc+=1; cc+=1
    return [a, b]
V = lambda db: (lambda e: e[5] == db)
def probe(label, hi, lo):
    before = L.latest()[3]
    t = send(dbl((0x00,0x05,hi,lo))); time.sleep(1.2)
    after = [e[3] for e in L.since(t, "eno1")]; changed = [x for x in after if x != before]
    log(f"{label:50s} payload {hi:02X} {lo:02X} from slot {before} -> {'NO CHANGE (stays %d)' % before if not changed else 'CHANGED to %s' % sorted(set(changed))}")
    time.sleep(0.2); trial("   forced volume -40.0 (double)", dbl(vol_payload(-40.0,-35)), V(-40.0), timeout=2.0); time.sleep(0.3)
    if L.latest()[3] != 0:
        probe_restore()
def probe_restore():
    t = send(dbl((0x00,0x05,0x00,0x00))); lat = wait_for(lambda e: e[3]==0, t, 2.0); log(f"   restore slot 0 via 0x0000 -> {lat} ms")
    time.sleep(0.2); trial("   forced volume -40.0 (double)", dbl(vol_payload(-40.0,-35)), V(-40.0), timeout=2.0); time.sleep(0.3)
probe("R1 float 16.0 from slot 0 (no enabled slot >= 16)", 0x41, 0x80)
probe("R2 float 29.0 from slot 0 (last valid index)", 0x41, 0xE8)
probe("R3 float 30.0 from slot 0 (out of range)", 0x41, 0xF0)
probe("R4 float 100.0 from slot 0", 0x42, 0xC8)
probe("R5 float 5.0 from slot 0 (disabled; next enabled is 14)", 0x40, 0xA0)
probe("R6 float 13.0 from slot 0 (disabled; next enabled is 14)", 0x41, 0x50)
probe("R7 float 4.5 from slot 0 (enabled 4 by truncation)", 0x40, 0x90)
log("final state", L.latest())
