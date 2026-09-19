from proto import *
assert crc16(b"123456789") == 0x29B1 and crc16(bytes(12)) == 0x84F9
assert packet(0,0,*POWER_ON)[:14].hex(" ") == "44 72 00 00 00 00 01 01 00 00 00 00 a0 bd"
mism = [(x, hex(db_convert(x)), hex(bf16(x))) for x in [i*0.5 for i in range(0, 201)] if db_convert(x) != bf16(x)]
print("dbConvert vs float32-top16 over 0..100 dB step 0.5: mismatches =", mism[:10], "count", len(mism))
# with sign bit: full command word vs bfloat16 of the signed dB
mism2 = [(x, hex(vol_word(x, None or 100.0)), hex(bf16(x))) for x in [-i*0.5 for i in range(0, 201)] if vol_word(x, 100.0) != bf16(x)]
print("signed word vs bf16(-dB): mismatches", len(mism2), mism2[:5])
print("source table bytes as float32:", {i: struct.unpack(">f", bytes(src_payload(i)[2:])+b"\0\0")[0] for i in [0,1,2,3,4,5,9,14]})
print("bf16(idx) for idx 0..15:", [hex(bf16(i)) for i in range(16)])
