from harness import *
log("=== RUN 4: sweep disabled indices 6..12 from slot 0 (is slot 9 an alias of 14?) ===")
log("ENVELOPE: source payloads only, forced -40.0 after every change, restore slot 0; no power cmds")
time.sleep(1); st = L.latest(); assert st and st[2] and not st[4] and st[5] == -40.0 and st[3] == 0, f"unexpected start state {st}"
pc = cc = 0
def dbl(payload):
    global pc, cc
    a = packet(pc, cc, *payload); pc+=1; cc+=1
    b = packet(pc, cc, *payload); pc+=1; cc+=1
    return [a, b]
V = lambda db: (lambda e: e[5] == db)
def restore():
    t = send(dbl((0x00,0x05,0x00,0x00))); lat = wait_for(lambda e: e[3]==0, t, 2.0); log(f"   restore slot 0 via 0x0000 -> {lat} ms")
    time.sleep(0.2); trial("   forced volume -40.0 (double)", dbl(vol_payload(-40.0,-35)), V(-40.0), timeout=2.0); time.sleep(0.3)
for idx in [9, 6, 7, 8, 10, 11, 12]:
    w = bf16(float(idx)); before = L.latest()[3]
    t = send(dbl((0x00,0x05,w>>8,w&0xFF))); time.sleep(1.2)
    after = [e[3] for e in L.since(t, "eno1")]; changed = [x for x in after if x != before]
    log(f"D{idx:02d} float {idx}.0 (disabled slot) from slot {before} payload {w>>8:02X} {w&0xFF:02X} -> {'NO CHANGE' if not changed else 'CHANGED to %s' % sorted(set(changed))}")
    if changed: time.sleep(0.2); trial("   forced volume -40.0 (double)", dbl(vol_payload(-40.0,-35)), V(-40.0), timeout=2.0); restore()
# and 9 again from slot 3 to confirm it is start-slot independent
t = send(dbl((0x00,0x05,0x40,0x40))); wait_for(lambda e: e[3]==3, t, 2.0); time.sleep(0.2); trial("   forced volume -40.0 (double)", dbl(vol_payload(-40.0,-35)), V(-40.0), timeout=2.0); time.sleep(0.3)
before = L.latest()[3]; t = send(dbl((0x00,0x05,0x41,0x10))); time.sleep(1.2)
after = [e[3] for e in L.since(t, "eno1")]; changed = [x for x in after if x != before]
log(f"D09b float 9.0 from slot {before} -> {'NO CHANGE' if not changed else 'CHANGED to %s' % sorted(set(changed))}")
time.sleep(0.2); trial("   forced volume -40.0 (double)", dbl(vol_payload(-40.0,-35)), V(-40.0), timeout=2.0); restore()
log("final state", L.latest())
