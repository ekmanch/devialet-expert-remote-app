import math, struct
def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc
def packet(pc, cc, b6, b7, b8=0, b9=0, bad_crc=False):
    d = bytearray(142)
    d[0:2] = b"\x44\x72"; d[2]=pc>>8; d[3]=pc&0xFF; d[4]=cc>>8; d[5]=cc&0xFF
    d[6]=b6; d[7]=b7; d[8]=b8; d[9]=b9
    c = crc16(d[:12]); 
    if bad_crc: c ^= 0x5A5A
    d[12]=c>>8; d[13]=c&0xFF
    return bytes(d)
def db_steps(steps):
    if steps == 0: return 0
    if steps == 1: return 0x3F00
    dbabs = steps*0.5
    shift = math.ceil(1 + math.log2(dbabs))
    term = (256 >> shift) if 0 <= shift < 32 else 0
    return (term + db_steps(steps-1)) & 0xFFFF
def db_convert(absdb): return db_steps(max(0, round(absdb/0.5)))
def vol_word(db, maxdb=-15.0):
    c = min(db, maxdb); w = db_convert(abs(c))
    if c < 0: w |= 0x8000
    return w
def bf16(x): return struct.unpack(">H", struct.pack(">f", x)[:2])[0]
def vol_payload(db, maxdb=-15.0):
    w = vol_word(db, maxdb); return (0x00, 0x04, w>>8, w&0xFF)
# Pinned byte pairs (confirmed on two amps; 0 is NaN, 3 is 3.5), else
# bfloat16(idx) — mirrors lib/networking/source_mapping.dart (Task 1.1.4).
SRC_PINNED = {0:0xFFE0, 1:0x3F80, 2:0x4000, 3:0x4060, 4:0x4080, 5:0x40A0, 14:0x4160}
def src_payload(idx):
    w = SRC_PINNED[idx] if idx in SRC_PINNED else bf16(float(idx))
    return (0x00,0x05,(w>>8)&0xFF,w&0xFF)
MUTE_ON=(0x01,0x07); MUTE_OFF=(0x00,0x07); POWER_ON=(0x01,0x01); POWER_OFF=(0x00,0x01)
