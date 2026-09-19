from harness import *
log("=== RUN 2: source-select encoding probes + sub-half-dB volume probe ===")
log("ENVELOPE: source payloads only (byte6/7 = 00 05), forced -40.0 double-send after every switch, restore slot 0; volume probe -40.25 only; no power cmds")
time.sleep(1); st = L.latest(); assert st and st[2] and not st[4] and st[5] == -40.0 and st[3] == 0, f"unexpected start state {st}"
pc = cc = 0
def dbl(payload):
    global pc, cc
    a = packet(pc, cc, *payload); pc+=1; cc+=1
    b = packet(pc, cc, *payload); pc+=1; cc+=1
    return [a, b]
SRC = lambda i: (lambda e: e[3] == i)
V = lambda db: (lambda e: e[5] == db)
def probe(label, hi, lo, expect_change_to=None):
    before = L.latest()[3]
    if expect_change_to is None:
        # expect NO change: wait the full window and report what happened
        t = send(dbl((0x00,0x05,hi,lo))); time.sleep(1.2)
        after = [e[3] for e in L.since(t, "eno1")]
        changed = [x for x in after if x != before]
        log(f"{label:60s} payload {hi:02X} {lo:02X} from slot {before} -> {'NO CHANGE (stays %d)' % before if not changed else 'CHANGED to %s' % sorted(set(changed))}")
    else:
        t = send(dbl((0x00,0x05,hi,lo))); lat = wait_for(SRC(expect_change_to), t, 2.0)
        log(f"{label:60s} payload {hi:02X} {lo:02X} from slot {before} -> {'slot %d in %d ms' % (expect_change_to, lat) if lat is not None else 'NOT slot %d (now %d)' % (expect_change_to, L.latest()[3])}")
    time.sleep(0.2)
    trial("   forced volume -40.0 (double)", dbl(vol_payload(-40.0, -35)), V(-40.0), timeout=2.0)
    time.sleep(0.5)

probe("S1 table bytes for status 3 (float 3.5)", 0x40, 0x60, 3)
probe("S2 table bytes for status 0 (float NaN)", 0xFF, 0xE0, 0)
probe("S3 float32 3.0 (hypothesis for status 3)", 0x40, 0x40, 3)
probe("S4 float32 0.0 (hypothesis for status 0)", 0x00, 0x00, 0)
probe("S5 float32 1.5 -> slot 1 (truncate) or 2 (round)?", 0x3F, 0xC0, 1)
probe("S6 float32 2.75 -> slot 2 (truncate) or 3 (round)?", 0x40, 0x30, 2)
probe("S7 float32 9.0 = current raw fallback for status 9 (slot disabled)", 0x41, 0x10, None)
probe("S8 float32 5.0 = table bytes for status 5 (slot disabled here)", 0x40, 0xA0, None)
probe("S9 float32 14.0 = table bytes for status 14", 0x41, 0x60, 14)
probe("S10 0x41C0 = 0x4000|(14<<5) without the >>1 (float 24.0)", 0x41, 0xC0, None)
probe("S11 float32 16.0 (bf16 of 16; slot disabled)", 0x41, 0x80, None)
probe("S12 float32 -1.0", 0xBF, 0x80, None)
probe("RESTORE via table bytes for status 0", 0xFF, 0xE0, 0)
# volume probe: -40.25 (bf16 exact 0xC221)
w = bf16(-40.25); log(f"volume probe -40.25 -> word {w:#06x}")
t = send(dbl((0x00,0x04,w>>8,w&0xFF))); time.sleep(1.0)
log("   broadcast vols after -40.25:", sorted(set(e[5] for e in L.since(t, 'eno1'))))
trial("RESTORE volume -40.0 (double)", dbl(vol_payload(-40.0, -35)), V(-40.0))
log("final state", L.latest())
