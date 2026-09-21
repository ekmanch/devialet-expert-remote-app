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
- `run5_boot.py <log> <mode>` — the 2026-09-21 boot / startup-volume /
  post-boot-hold run (`docs/protocol-verification-2026-09-21-boot.md`).
  Modes `t0` (control boot, app stopped), `watch` (no sends; follows an
  Off→On the phone causes), `t3` (harness boot with the app watching),
  `set35` / `set40`, `restore`. It is the only script that sends power
  commands; its envelope is in its header. Set `SHOTS=<dir>` to grab adb
  screenshots at +0.3 / +1.0 s after the first On packet. The listener
  tuple carries the raw volume byte as index 6 since this run.

Run from this directory with the amp powered on and idle:
`python3 run1.py run1.log`. The amp IP is hardcoded in `harness.py`
(`AMP`); the interface names (`eno1`, `wlan0`) are this dev machine's.
Every run asserts the start state (on, slot 0, −40.0 dB, unmuted) and
aborts otherwise (run5: On, slot 0, unmuted). No root needed — the
listener is an ordinary UDP socket, so no pcap was taken; the log *is*
the raw inbound capture. It cannot see the phone's unicast commands on
45455: when the app is the thing under test, its send instants come from
the app's `[amp]` trace over `adb logcat` (`docs/architecture.md` §15).
