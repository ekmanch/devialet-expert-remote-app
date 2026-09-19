# Architecture — the state owner

Written design for Tasks 3.0.x / 3.1.x (TODO.md: "a written design precedes
any control wiring"). Describes what is implemented as of 2026-09-19 and
the seams left for the tasks that follow. The KDE widget's daemon is the
reference design; where this doc and `docs/protocol.md` disagree, the
protocol doc wins on wire facts.

## 1. Scope

Implemented: one Riverpod-owned amp state fed by live UDP broadcasts, a
discovery map keyed by sender IP, staleness on a monotonic clock, the
selection model (explicit choice vs. never chosen), a pure derivation into
the view state the UI renders, a 400 ms pending-command mask over volume /
mute / power / source with an unmasked confirmed channel, and the
synchronous-write → send → rollback intent shape.

Deferred: the boot state machine (3.2.x — the `bootDeadline` seam and the
Booting derivation exist, nothing enters Booting yet), persistence (3.3.x —
selection is in-memory), settings-driven volume range (3.4.x), the actual
command sends (3.5–3.9 — intents are display-only through
`NoopCommandSink`), mDNS names (3.9.5), feedback (3.10.x).

## 2. Layers

```
lib/networking/   pure Dart, zero Flutter imports: packets, codecs, UdpTransport, DevialetClient
lib/domain/       Riverpod owner + pure model/derivation (imports riverpod, not flutter)
lib/ui/           widgets; read controlViewStateProvider, call ampStateProvider.notifier
```

`UdpTransport.bindAndListen` yields `UdpDatagram = (data, senderAddress)`;
`DevialetClient.statusReports` yields `AmpStatusReport = (senderIp, status)`.
The sender is what keys everything above; it is a `String` so no `dart:io`
type leaves the transport.

## 3. The one owner (`lib/domain/amp_state_owner.dart`)

- `ampStateProvider` — `NotifierProvider<AmpStateOwner, AmpState>`, **not**
  autoDispose. On build it starts the client listening, subscribes to
  `statusReports` → `ingest`, subscribes to the 1 s tick, and on dispose
  cancels both and stops listening. It owns the socket lifetime;
  `ampStatusStreamProvider` is only a read-only view for the debug screen.
- `controlViewStateProvider` — `Provider<ControlViewState>` derived from
  the raw model. Same name as the Task 2.0.x fake, so every `ref.watch` in
  the UI stayed as it was. `ControlViewState` has value equality, so a 5 Hz
  broadcast that changes nothing visible does not rebuild the screen.
- `confirmedAmpStateProvider` — `Provider<ConfirmedAmpState?>`: what the
  amp last *reported* for the selected amp, never through a pending slot,
  with `receivedAt` so each broadcast is a distinct value. Feedback
  (3.10.x) listens here, never to the gesture (checklist 25).

Views keep no copies of volume / mute / power / source / selection. The
only widget-local value is the dial's in-progress drag (`_dragDb` in
`control_screen.dart`), which is gesture state, not a copy — it is
discarded on release and the owner's value takes over (TODO 3.6.4).

## 4. Raw model (`amp_state.dart`, `amp_tracker.dart`)

```
AmpState { amps: Map<ip, TrackedAmp>, selectedIp?, hasExplicitSelection, now, floorDb, ceilingDb }
TrackedAmp { ip, status (last broadcast, verbatim), lastSeen, modelName?, bootDeadline?,
             pendingVolumeDb?, pendingMuted?, pendingPower?, pendingSource? }
PendingValue<T> { value, deadline }   // confirmed by exact equality, expired when now >= deadline
```

- `ingest(report, now)`: replace the entry's `status`/`lastSeen`, **carry
  forward** model name, boot deadline and every pending slot (a broadcast
  must not wipe an armed mask), then `resolvePending(now)`.
- `tick(now)`: `resolvePending(now)` on every entry — expiries with no
  broadcast in between.
- `amps` is **never evicted** (KDE). A silent amp is offline
  (`now − lastSeen ≥ 8 s`), not forgotten.

## 5. Time

One injectable monotonic clock (`MonotonicClock`, a `Stopwatch` in
production) and one 1 s tick stream. Every deadline is a `Duration` on
that clock compared on each ingest and each tick — **no per-field timers**
(KDE `POLL_TICK`). Constants in `amp_tracker.dart`: `kPendingWindow` 400 ms,
`kStaleAfter` 8 s, `kBootTimeout` 20 s — all from `docs/protocol.md`,
"Timing facts". Tests inject `FakeClock` / `ManualTicker`.

## 6. Selection

- `selectedIp` + `hasExplicitSelection`: "chose None" (`null`, `true`) is
  distinct from "never chose" (`null`, `false`) — checklist 4 and the KDE
  Phase 4.1 bug.
- `effectiveIp`: the explicit selection; else, only when never chosen and
  exactly **one** amp is known (known, not online — KDE), that amp
  (auto-select-if-alone). 0 or 2+ known: nothing, don't guess.
- A never-heard manual IP is a valid selection, shown not-connected until
  a broadcast from it arrives; staleness alone governs connectedness.
- **Silent amp (owner decision 2026-09-19, TODO 3.0.8):** presented exactly
  as no amplifier — hidden from the list, `selectedAmp == null`, footer
  "Not connected" — while `selectedIp` is untouched, so the next broadcast
  from that IP reconnects without a tap. The view carries `selectedIp` so
  Task 3.9.x can render an offline row instead of highlighting "None".

## 7. Derivation (`deriveControlView`)

Pure: same model, same view. Online selected amp → connected shape
(`AmpRef(id: ip, name: deviceName, model: modelName, ip)`, `power` from
`powerPhaseAt(now)`, **masked** mute / volume / source, enabled slots as
`SourceItem`s, floor / ceiling). Otherwise the not-connected shape:
`selectedAmp null`, power Off, unmuted, no sources, and `volumeDb` set to
the floor as a sentinel that the UI never formats because it checks
`hasAmp` first (checklist 5; a `double?` is the honest follow-up, noted in
TODO). `knownAmps` = online amps in numeric IP order so the list only
reorders when the IP set changes. Only the selected amp's broadcasts reach
the control fields; every broadcast feeds the list (3.0.5).

## 8. Pending-command mask + confirmed channel (3.1.0)

| Field  | Pending slot      | Confirmed by (exact)        | Displayed             |
|--------|-------------------|-----------------------------|-----------------------|
| volume | `pendingVolumeDb` | `status.volumeDb` (0.5 dB grid, decode is exact) | `pending?.value ?? status` |
| mute   | `pendingMuted`    | `status.isMuted`            | same                  |
| power  | `pendingPower`    | `status.isPoweredOn`        | same (+ Booting overlay) |
| source | `pendingSource`   | `status.activeSourceIndex`  | same                  |

Rules: a local write arms the slot with `now + 400 ms`; a broadcast that
equals the value clears it (confirmed); a broadcast that differs is
recorded as `status` but not displayed until the deadline passes (fall back
to the amp's value); a newer write **replaces value and deadline**
(re-arm, so a sustained gesture never leaves a gap). The mask lives in the
owner and is applied once in the derivation, so every input path is
covered by construction — gotchas #1/#2 cannot come back one widget at a
time. `test/domain/amp_state_test.dart` reproduces the late pre-change
broadcast and proves the assertion catches the bug by running the same
sequence unmasked (checklist 20).

## 9. Intents

`setVolumeDb`, `stepVolume`, `toggleMute`, `togglePower`, `selectSource`:
gate on the derived view (`volumeGroupEnabled` / `powerEnabled` — the
3.2.1 predicate seam), quantize/clamp, **write the pending slot
synchronously**, then `await sink…`; on a throw, clear the slot (rollback,
checklist 3). `stepVolume` steps from the displayed value so rapid taps
accumulate. `AmpCommandSink` is `NoopCommandSink` this session; Tasks
3.5–3.9 provide a `DevialetClient`-backed sink and swap the provider body.
Consequence today: an optimistic change on a real amp reverts after 400 ms.

## 10. Seams

- 3.2.x: `markBooting(ip)` sets `bootDeadline` (not extended by repeats);
  `powerPhaseAt` renders Booting; `resolvePending` clears it on On or
  timeout. `togglePower`'s off→on edge should call it instead of arming
  `pendingPower(true)`.
- 3.3.x: persist `selectedIp` + `hasExplicitSelection`; restore before the
  owner builds.
- 3.4.x: `setVolumeRange` replaces `kDefaultFloorDb` / `kDefaultCeilingDb`.
- 3.9.5: `setModelName(ip, model)`.
- 3.10.x: `confirmedAmpStateProvider`.

## 11. Debug simulated amp (`lib/ui/debug/simulated_amp.dart`)

Opt-in from the debug bar: synthetic status packets for 192.0.2.22/.23/.24
(TEST-NET-1, never routable) built with `buildStatusPacket` and parsed with
`tryParse`, fed through `AmpStateOwner.ingest` at the amp's real 5 Hz.
`seedFromControlView` reproduces any `ControlViewState` fixture, which is
also how widget tests seed the real owner. Limits: Booting is only the 20 s
deadline; "Not responding" stops broadcasting and the view flips after the
real 8 s; optimistic changes revert after 400 ms.

## 12. Testing

No socket, no wall clock: `FakeUdpTransport`, `FakeClock`, `ManualTicker`
via provider overrides (`test/ui/support/pump_control.dart::hermeticApp`).
Pure tests on `AmpState` / `deriveControlView`; owner tests through
`ProviderContainer.test`; the simulated amp is pinned to the fixtures the
widget state table already uses.

## 13. Checklist mapping

1 mask in the owner keyed on send time (§8) · 2 one owner, no view copies
(§3) · 3 synchronous write + rollback (§9) · 4 explicit-selection flag (§6)
· 5 `hasAmp` before any reading (§7) · 6 gate from one predicate (§9) ·
7 confirmed channel + boot seam (§3, §10) · 12/13 re-derive from the whole
status on every ingest (§4, §7) · 19 fakes against disposable containers
(§12) · 20 the unmasked counter-test (§8) · 27 TEST-NET fixtures (§11) ·
28 the mask and the gate live in the one function everything passes
through (§8, §9).
