from harness import *
log("=== RUN 1: baseline, control, counters, duplicates, CRC, mute, Wi-Fi ===")
log("ENVELOPE: volume only in {-41.0,-40.5,-40.0} (ceiling arg -35), no power cmds, mute restored off, no source cmds in this run")
time.sleep(1); st = L.latest(); assert st and st[2] and not st[4] and st[5] == -40.0 and st[3] == 0, f"unexpected start state {st}"
log("start state", st)

# --- passive baseline: 30 s, count broadcasts per interface, delay of the wlan0 copy
tb = time.monotonic()-T0; time.sleep(30)
ev = L.since(tb); e = [x for x in ev if x[1]=="eno1"]; w = [x for x in ev if x[1]=="wlan0"]
gaps = [round((b[0]-a[0])*1000) for a,b in zip(e, e[1:])]
log(f"baseline 30 s: eno1={len(e)} wlan0={len(w)} other={len(ev)-len(e)-len(w)}; eno1 gap ms min/med/max = {min(gaps)}/{sorted(gaps)[len(gaps)//2]}/{max(gaps)}")
# wlan0 copy delay: match each wlan0 packet to the nearest preceding eno1 packet
dl = []
for x in w:
    prev = [y for y in e if y[0] <= x[0]]
    if prev: dl.append(round((x[0]-prev[-1][0])*1000))
log(f"wlan0 copy delay after eno1 copy (ms): min/med/max = {min(dl)}/{sorted(dl)[len(dl)//2]}/{max(dl)}  (n={len(dl)}); wlan0 loss vs eno1 = {100*(1-len(w)/len(e)):.0f}%")

# --- control: app-style double send, contiguous counters from (0,0)
pc = cc = 0
def app_double(payload):
    global pc, cc
    a = packet(pc, cc, *payload); pc=(pc+1)&0xFFFF; cc=(cc+1)&0xFFFF
    b = packet(pc, cc, *payload); pc=(pc+1)&0xFFFF; cc=(cc+1)&0xFFFF
    return [a, b]
V = lambda db: (lambda e: e[5] == db)
ok = trial("E0 control: double send, contiguous ctr, vol -40.5", app_double(vol_payload(-40.5, -35)), V(-40.5))
assert ok is not None, "control failed - aborting before anything else"
trial("E0 control: double send, contiguous ctr, vol -40.0", app_double(vol_payload(-40.0, -35)), V(-40.0))

# --- E1: single send, contiguous counters, x20 alternating (eno1)
res = []
for i in range(20):
    db = -40.5 if i % 2 == 0 else -40.0
    p = packet(pc, cc, *vol_payload(db, -35)); pc=(pc+1)&0xFFFF; cc=(cc+1)&0xFFFF
    res.append(trial(f"E1 single send #{i+1:02d} contiguous ctr ({pc-1},{cc-1}) vol {db}", [p], V(db)))
    time.sleep(0.3)
good = [r for r in res if r is not None]
log(f"E1 SUMMARY single-send eno1: {len(good)}/20 applied; latency ms min/med/max = {min(good)}/{sorted(good)[len(good)//2]}/{max(good)}")

# --- E2: counters frozen at (0,0), single send x6
res = []
for i in range(6):
    db = -40.5 if i % 2 == 0 else -40.0
    res.append(trial(f"E2 single send, counters frozen (0,0), vol {db}", [packet(0,0,*vol_payload(db,-35))], V(db))); time.sleep(0.3)
log(f"E2 SUMMARY frozen (0,0): {sum(r is not None for r in res)}/6 applied")

# --- E3: random / decreasing / mismatched counters, single send
cases = [(0xFFFF,0xFFFF),(0x1234,0x9ABC),(0x0005,0x0001),(0x0002,0x0000),(0x8000,0x0000),(0x0000,0x8000)]
res = []
for i,(p_,c_) in enumerate(cases):
    db = -40.5 if i % 2 == 0 else -40.0
    res.append(trial(f"E3 single send, counters ({p_:#06x},{c_:#06x}), vol {db}", [packet(p_,c_,*vol_payload(db,-35))], V(db))); time.sleep(0.3)
log(f"E3 SUMMARY arbitrary counters: {sum(r is not None for r in res)}/6 applied")

# --- E4: identical bytes twice (same counters), and 5 identical copies
res = []
for i in range(4):
    db = -40.5 if i % 2 == 0 else -40.0
    p = packet(pc, cc, *vol_payload(db, -35)); pc=(pc+1)&0xFFFF; cc=(cc+1)&0xFFFF
    res.append(trial(f"E4 identical bytes x{2 if i<2 else 5}, vol {db}", [p]*(2 if i<2 else 5), V(db))); time.sleep(0.3)
log(f"E4 SUMMARY identical duplicates: {sum(r is not None for r in res)}/4 applied")

# --- E5: bad CRC, single send x4 (expect NOT applied if CRC is checked)
res = []
for i in range(4):
    db = -40.5 if i % 2 == 0 else -40.0
    p = packet(pc, cc, *vol_payload(db, -35), bad_crc=True); pc=(pc+1)&0xFFFF; cc=(cc+1)&0xFFFF
    res.append(trial(f"E5 BAD CRC single send, vol {db}", [p], V(db), timeout=1.0)); time.sleep(0.3)
log(f"E5 SUMMARY bad CRC: {sum(r is not None for r in res)}/4 applied (0 = amp checks CRC)")
# E5b: bad CRC, double send, then a correct one to resync state
p = packet(pc, cc, *vol_payload(-40.5, -35), bad_crc=True); q = packet(pc+1, cc+1, *vol_payload(-40.5, -35), bad_crc=True); pc+=2; cc+=2
trial("E5b BAD CRC double send, vol -40.5", [p,q], V(-40.5), timeout=1.0)
# E5c: wrong magic, good CRC
p = bytearray(packet(pc, cc, *vol_payload(-40.5,-35))); p[0]=0x45; c=crc16(p[:12]); p[12]=c>>8; p[13]=c&0xFF; pc+=1; cc+=1
trial("E5c wrong magic byte0 (0x45), CRC recomputed, vol -40.5", [bytes(p)], V(-40.5), timeout=1.0)
# E5d: truncated packet (14 bytes only, no padding)
p = packet(pc, cc, *vol_payload(-40.5,-35))[:14]; pc+=1; cc+=1
trial("E5d truncated to 14 bytes (no padding), vol -40.5", [p], V(-40.5), timeout=1.0)
trial("resync: double send vol -40.0", app_double(vol_payload(-40.0,-35)), V(-40.0))

# --- E6: mute single send
M = lambda m: (lambda e: e[4] == m)
for i in range(2):
    p = packet(pc, cc, *MUTE_ON); pc+=1; cc+=1
    trial("E6 mute ON single send", [p], M(True)); time.sleep(0.3)
    p = packet(pc, cc, *MUTE_OFF); pc+=1; cc+=1
    trial("E6 mute OFF single send", [p], M(False)); time.sleep(0.3)

# --- E7: Wi-Fi single send x20 via wlan0 (SO_BINDTODEVICE)
tx0 = int(open("/sys/class/net/wlan0/statistics/tx_packets").read())
res = []
for i in range(20):
    db = -40.5 if i % 2 == 0 else -40.0
    p = packet(pc, cc, *vol_payload(db, -35)); pc=(pc+1)&0xFFFF; cc=(cc+1)&0xFFFF
    res.append(trial(f"E7 WLAN single send #{i+1:02d} vol {db}", [p], V(db), iface="wlan0")); time.sleep(0.3)
tx1 = int(open("/sys/class/net/wlan0/statistics/tx_packets").read())
good = [r for r in res if r is not None]
log(f"E7 SUMMARY single-send wlan0: {len(good)}/20 applied; latency ms min/med/max = {min(good) if good else '-'}/{sorted(good)[len(good)//2] if good else '-'}/{max(good) if good else '-'}; wlan0 tx_packets delta={tx1-tx0} (control: must be >=20)")
# E7b: Wi-Fi double send x10
res = []
for i in range(10):
    db = -40.5 if i % 2 == 0 else -40.0
    res.append(trial(f"E7b WLAN double send #{i+1:02d} vol {db}", app_double(vol_payload(db,-35)), V(db), iface="wlan0")); time.sleep(0.3)
log(f"E7b SUMMARY double-send wlan0: {sum(r is not None for r in res)}/10 applied")

trial("RESTORE: double send vol -40.0", app_double(vol_payload(-40.0,-35)), V(-40.0))
p = packet(pc, cc, *MUTE_OFF); pc+=1; cc+=1; trial("RESTORE: mute off", [p], M(False))
log("final state", L.latest())
