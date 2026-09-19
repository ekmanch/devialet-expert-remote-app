import socket, sys, time
dur = float(sys.argv[1]) if len(sys.argv) > 1 else 6
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
s.bind(("0.0.0.0", 45454)); s.settimeout(0.5)
t0 = time.monotonic(); n = 0; last = None
def dec(d):
    name = d[19:50].decode("utf-8","replace").strip("\x00 ")
    pw = (d[562] & 0x80) != 0; src = (d[563] & 0x3C) >> 2; mute = (d[563] & 0x02) != 0
    vol = (d[565] - 195) / 2
    srcs = [(i, d[53+i*17:53+i*17+16].decode("utf-8","replace").strip("\x00 ")) for i in range(30) if d[52+i*17] == 0x31]
    return name, pw, src, mute, vol, srcs
while time.monotonic() - t0 < dur:
    try: d, a = s.recvfrom(2048)
    except socket.timeout: continue
    n += 1
    if len(d) < 566: print(f"{time.monotonic()-t0:7.3f} {a[0]} SHORT {len(d)}"); continue
    name, pw, src, mute, vol, srcs = dec(d)
    print(f"{time.monotonic()-t0:7.3f} {a[0]}:{a[1]} len={len(d)} name={name!r} power={'on' if pw else 'off'} src={src} mute={mute} vol={vol:+.1f}")
    last = srcs
print(f"packets={n}")
if last: print("enabled sources:", last)
