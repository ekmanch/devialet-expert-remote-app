# Protocol probe harness (Python, dev-machine only)

Throwaway-grade but reproducible scripts behind
`docs/protocol-verification-2026-09-19.md`. Not part of the app; nothing
here is imported by `lib/`. Python 3, standard library only.

- `proto.py` — 142-byte command builder (CRC16/CCITT-FALSE, float16-top
  encodings), independent of the Dart code so it can cross-check it.
- `xcheck.dart` / `bf16_check.py` — prove `proto.py` and
  `lib/networking/` emit identical bytes, and that `dbConvert` equals the
  top 16 bits of an IEEE-754 float32 over 0..100 dB.
- `harness.py` — status listener (tags each broadcast with the receiving
  interface via `IP_PKTINFO`), `send()` with optional `SO_BINDTODEVICE`,
  and `trial()` which waits for the confirming broadcast and reports
  latency.
- `run1.py` … `run4.py` — the experiments, in the order they were run.
  Each declares its safety envelope in its first log lines and restores
  the amp's state at the end.
- `listen.py` — 6-second decode of whatever is broadcasting on 45454.

Run from this directory with the amp powered on and idle:
`python3 run1.py run1.log`. The amp IP is hardcoded in `harness.py`
(`AMP`); the interface names (`eno1`, `wlan0`) are this dev machine's.
Every run asserts the start state (on, slot 0, −40.0 dB, unmuted) and
aborts otherwise. No root needed — the listener is an ordinary UDP
socket, so no pcap was taken; the log *is* the raw inbound capture.
