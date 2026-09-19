# Architecture — the state owner

Written design for Tasks 3.0.x / 3.1.x (TODO.md: "a written design precedes
any control wiring"). Describes what is implemented as of 2026-09-19 and
the seams left for the tasks that follow. The KDE widget's daemon is the
reference design; where this doc and `docs/protocol.md` disagree, the
protocol doc wins on wire facts.

## 1. Scope

Implemented (3.0.x / 3.1.x): one Riverpod-owned amp state fed by live UDP
broadcasts, a discovery map keyed by sender IP, staleness on a monotonic
clock, the selection model (explicit choice vs. never chosen), a pure
derivation into the view state the UI renders, a 400 ms pending-command
mask over volume / mute / power / source with an unmasked confirmed
channel, and the synchronous-write → send → rollback intent shape.
Implemented (3.2.x): the Off / Booting / On machine with the 20 s timeout,
the `commandsAllowed` / `powerCommandAllowed` predicates, the 500 ms
post-boot startup-volume send and the 1500 ms display hold; **power and
the startup volume are sent for real** through `DevialetClientCommandSink`.

Deferred: persistence (3.3.x — selection is in-memory), settings-driven
volume range and startup value (3.4.x — `kStartupVolumeDb` is the seam),
the user's volume / mute / source sends (3.6–3.8 — those sink methods are
no-ops), mDNS names (3.9.5), feedback (3.10.x).

## 2. Layers

```
lib/networking/   pure Dart, zero Flutter imports: packets, codecs, UdpTransport, DevialetClient
lib/domain/       Riverpod owner + pure model/derivation (imports riverpod, not flutter)
lib/domain/debug/ synthetic status packets + the command-aware simulated amp (debug builds)
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
TrackedAmp { ip, status (last broadcast, verbatim), lastSeen, modelName?, boot?,
             pendingVolumeDb?, pendingMuted?, pendingPower?, pendingSource? }
PendingValue<T> { value, deadline }   // confirmed by exact equality, expired when now >= deadline
BootInProgress { deadline, target, confirmedAt?, startupSent }   // exists only for a self-initiated power-on
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
`kStaleAfter` 8 s, `kBootTimeout` 20 s, `kStartupVolumeDelay` 500 ms,
`kBootHold` 1500 ms — all from `docs/protocol.md`, "Timing facts". Because
deadlines are checked on ingest (5 Hz) and the tick, the startup send lands
at +500…+700 ms after the confirming packet and never earlier — on the
safe side of gotcha #9's measured +394 ms. Tests inject `FakeClock` /
`ManualTicker`.

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
| post-boot hold | `pendingVolumeDb` armed with `(boot.target, confirmedAt + 1500 ms)` | `status.volumeDb == target` | the target; the −42 misreport is recorded, not shown |

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

`setVolumeDb`, `stepVolume`, `toggleMute`, `selectSource`: gate on
`commandsAllowed` (On and connected — 3.2.1), quantize/clamp, **write the
pending slot synchronously**, then `await sink…`; on a throw, clear the
slot (rollback, checklist 3). `stepVolume` steps from the displayed value
so rapid taps accumulate. Inside a confirmed post-boot hold `setVolumeDb`
keeps the hold's deadline and re-targets the pending startup send, so a
user value is never overridden by the default (gotcha #9).

`togglePower` (3.2.0), gated on `powerCommandAllowed`: On → Off arms
`pendingPower(false)`, drops any boot record and sends; Off → On calls
`markBooting` (a `BootInProgress` with the clamped startup target) and
sends — no optimistic On, the amp's broadcast confirms it or the 20 s
deadline falls back to Off; Booting → no-op, so repeats don't extend; an Off
that is only optimistic (the amp still reports On) is cancelled without a
boot record, so a stale On cannot "confirm" a boot. `_runBootFollowUps`,
after every ingest and tick, sends the startup volume once per confirmed
boot at ≥ +500 ms (`startupSent` flipped before the await), for the amp
that was booted even if the selection moved; a failed send drops record
and hold, no retry. An external On (front panel, remote) or a late On
after the timeout creates no record: no send, no hold — gotcha #8 stays
visible by decision.

The sink is `DevialetClientCommandSink`: `setPower` and `sendStartupVolume`
are real; `setVolumeDb` / `setMute` / `selectSource` are no-ops until Tasks
3.6 / 3.7 / 3.8, so those optimistic changes still revert after 400 ms.

## 10. Seams

- 3.3.x: persist `selectedIp` + `hasExplicitSelection`; restore before the
  owner builds.
- 3.4.x: `setVolumeRange` replaces `kDefaultFloorDb` / `kDefaultCeilingDb`;
  `kStartupVolumeDb` (read through `AmpState.startupVolumeTarget`) becomes
  the persisted startup setting (3.4.8).
- 3.5.1: route every UI entry point through `commandsAllowed` /
  `powerCommandAllowed`. 3.6 / 3.7 / 3.8: flip the corresponding no-op
  method of `DevialetClientCommandSink`.
- 3.9.5: `setModelName(ip, model)`.
- 3.10.x: `confirmedAmpStateProvider`.

## 11. Debug simulated amp (`lib/domain/debug/simulated_amp.dart`)

Opt-in from the debug bar: synthetic status packets for 192.0.2.22/.23/.24
(TEST-NET-1, never routable) built with `buildStatusPacket` and parsed with
`tryParse`, fed through `AmpStateOwner.ingest` at the amp's real 5 Hz.
`seedFromControlView` reproduces any `ControlViewState` fixture, which is
also how widget tests seed the real owner.

Since 3.2.x the sim is **command-aware**: in debug builds
`debugCommandSinkOverride` (installed by `main.dart` and the test harness)
routes commands for 192.0.2.x to it and everything else to the real sink.
It behaves like the measured amp: power-on boots in 16 s while
broadcasting Off; the first On packet carries the pre-shutdown byte, then
raw 111 (−42.0) until any volume command lands; volume commands within
200 ms of the first On are dropped (gotcha #9); other commands apply after
100 ms; power-off is immediate. Its deadlines are evaluated on its own
200 ms tick against the injected clock. So the debug bar's "Booting" now
completes, the owner sends the startup volume to the sim, and the misreport
is held and corrected — the whole loop without hardware. "Not responding"
stops broadcasting and the view flips after the real 8 s; the user's
volume / mute / source changes still revert after 400 ms (3.6–3.8).

## 12. Testing

No socket, no wall clock: `FakeUdpTransport`, `FakeClock`, `ManualTicker`
via provider overrides (`test/ui/support/pump_control.dart::hermeticApp`).
Pure tests on `AmpState` / `deriveControlView`; owner tests through
`ProviderContainer.test` with recording/throwing sinks; the simulated amp
is pinned to the fixtures the widget state table already uses and driven
with `tick()`. Every protective mechanism has a counter-test proving the
positive assertion fails without it (checklist 20): the mask (`applyUnmasked`
shows the stale broadcast leaking), the hold (`applyUnheld` shows −42
leaking), and the startup delay (an early volume command is dropped by the
simulated amp, as measured on the real one).

## 13. Checklist mapping

1 mask in the owner keyed on send time (§8) · 2 one owner, no view copies
(§3) · 3 synchronous write + rollback (§9) · 4 explicit-selection flag (§6)
· 5 `hasAmp` before any reading (§7) · 6 gate from one predicate (§9) ·
7 confirmed channel + boot seam (§3, §10) · 12/13 re-derive from the whole
status on every ingest (§4, §7) · 19 fakes against disposable containers
(§12) · 20 the unmasked counter-test (§8) · 27 TEST-NET fixtures (§11) ·
28 the mask and the gate live in the one function everything passes
through (§8, §9).
