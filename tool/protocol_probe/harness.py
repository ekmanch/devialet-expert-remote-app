import socket, struct, time, threading, random, sys, json
from proto import *
AMP = "192.168.0.22"; CMD_PORT = 45455
IFNAMES = {}
import os
for n in os.listdir("/sys/class/net"):
    try: IFNAMES[int(open(f"/sys/class/net/{n}/ifindex").read())] = n
    except: pass
LOG = open(sys.argv[1] if len(sys.argv) > 1 else "run.log", "a")
T0 = time.monotonic()
def log(*a):
    line = f"{time.monotonic()-T0:8.3f} " + " ".join(str(x) for x in a)
    print(line, flush=True); LOG.write(line + "\n"); LOG.flush()

class Listener(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self.s.setsockopt(socket.IPPROTO_IP, socket.IP_PKTINFO, 1)
        self.s.bind(("0.0.0.0", 45454)); self.s.settimeout(0.2)
        self.lock = threading.Lock(); self.events = []  # (t, iface, power, src, mute, vol, raw)  -- raw = byte 565, added for run5
        self.verbose = False
    def run(self):
        while True:
            try: d, anc, flags, addr = self.s.recvmsg(2048, 64)
            except socket.timeout: continue
            iface = "?"
            for lvl, typ, data in anc:
                if lvl == socket.IPPROTO_IP and typ == socket.IP_PKTINFO:
                    iface = IFNAMES.get(struct.unpack("i", data[:4])[0], "?")
            if len(d) < 566 or addr[0] != AMP: continue
            ev = (time.monotonic()-T0, iface, (d[562]&0x80)!=0, (d[563]&0x3C)>>2, (d[563]&0x02)!=0, (d[565]-195)/2, d[565])
            with self.lock: self.events.append(ev)
            if self.verbose: log("  bcast", iface, f"power={ev[2]} src={ev[3]} mute={ev[4]} vol={ev[5]:+.1f} raw={ev[6]}")
    def since(self, t, iface=None):
        with self.lock: return [e for e in self.events if e[0] >= t and (iface is None or e[1] == iface)]
    def latest(self, iface="eno1"):
        with self.lock:
            for e in reversed(self.events):
                if e[1] == iface: return e
        return None

L = Listener(); L.start()

def send(pkts, iface=None, gap=0.0):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if iface: s.setsockopt(socket.SOL_SOCKET, socket.SO_BINDTODEVICE, iface.encode())
    s.bind(("0.0.0.0", 0))
    t = time.monotonic()-T0
    for i, p in enumerate(pkts):
        if i and gap: time.sleep(gap)
        s.sendto(p, (AMP, CMD_PORT))
    s.close(); return t

def wait_for(pred, t_send, timeout=1.5):
    """Returns latency (ms) to the first eno1 broadcast after t_send satisfying pred, or None."""
    deadline = time.monotonic()-T0 + timeout
    while time.monotonic()-T0 < deadline:
        for e in L.since(t_send, "eno1"):
            if pred(e): return round((e[0]-t_send)*1000)
        time.sleep(0.01)
    return None

def trial(label, pkts, pred, iface=None, gap=0.0, timeout=1.5):
    t = send(pkts, iface, gap)
    lat = wait_for(pred, t, timeout)
    st = L.latest()
    log(f"{label:55s} -> {'OK %4d ms' % lat if lat is not None else 'NOT APPLIED'}   (state src={st[3]} mute={st[4]} vol={st[5]:+.1f})")
    return lat
