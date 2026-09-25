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

Implemented (3.3.x): the persisted, self-healed settings object
(`lib/domain/settings/`, §14) — the owner starts from the persisted
selection, limits and startup volume, and user selections persist (3.9.1).

Deferred: the Settings screen and theme consumption (3.4.x), the wire-side
ceiling from settings (3.4.7 / 1.1.3), the user's volume / mute / source
sends (3.6–3.8 — those sink methods are no-ops), feedback (3.10.x).
mDNS names arrived with 3.9.5 (§17).

## 2. Layers

```
lib/networking/   pure Dart, zero Flutter imports: packets, codecs, UdpTransport, DevialetClient,
                  parseModelName, the ModelNameSource seam + its multicast_dns adapter (§17)
lib/domain/       Riverpod owner + pure model/derivation (imports riverpod, not flutter)
lib/domain/settings/ typed settings, store adapters, hydration, settings owner (§14)
lib/domain/debug/ synthetic status packets + the command-aware simulated amp (debug builds)
lib/platform/     platform channels (the multicast lock, the iOS Bonjour source) — the only
                  Flutter imports outside lib/ui/ and main.dart; not lib/ui/platform/ (widgets)
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
  broadcast that changes nothing visible does not rebuild the screen — and
  a silent amp's "Last seen …" (`AmpRef.silentFor`) is carried *quantized*
  to what the sheet prints (just now / minutes / hours), so the 1 s tick
  changes the view only when a label would (3.9.0).
- `confirmedAmpStateProvider` — `Provider<ConfirmedAmpState?>`: what the
  amp last *reported* for the selected amp, never through a pending slot,
  with `receivedAt` so each broadcast is a distinct value. Feedback
  (3.10.x) listens here, never to the gesture (checklist 25).

Views keep no copies of volume / mute / power / source / selection, and
since 3.8.2 not of *which sheet is open* either (`AmpState.visibleSheet`,
§16). The only widget-local value is the dial's in-progress drag
(`_dragDb` in `control_screen.dart`), which is gesture state, not a copy —
it is discarded on release and the owner's value takes over (TODO 3.6.4).

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
- **Persisted** (3.9.1, done in 3.3.x) as `selected_ip` +
  `has_explicit_selection` and restored in `AmpStateOwner.build()`, so a
  chosen amp reconnects after a restart with no tap and "chose None" is
  never resurrected by auto-select. Only user intents (`selectIp`,
  `selectAmp`, `addManualAmp`) persist; `seedSelection` / `setVolumeRange`
  are the seeding and debug seams and never touch the store (checklist 19).
- **Silent amp — the waiting phase (owner's v44 mockups, 2026-09-24,
  revising the 2026-09-19 "no third presentation" decision of TODO
  3.0.8):** a selection that is not reachable — silent for 8 s, or a typed
  / restored IP never heard — is `ConnectionPhase.waiting`: still named on
  the card ("Reconnecting…" for an amp heard before, "Connecting…" for one
  never heard, the pulsing accent ring), still checked in the sheet under
  the "Not responding" group, every control inert (`hasAmp` is false) and
  no reading (`volumeDb == null`). `selectedIp` is untouched, so the next
  broadcast from that IP reconnects without a tap. "None" is current only
  in `notConnected` (nothing selected).
- **Typed IP (3.9.3):** `AmpState.manualIp` is the last IP entered by hand
  in this process — transient, never persisted (checklist 4: not a third
  sentinel; the two-state selection is untouched). The derivation reads it
  only for the never-heard synthetic row's "MANUAL" tag, so hearing the IP
  or choosing another amp retires the tag by itself; after a restart a
  typed IP is indistinguishable from a discovered one and shows untagged.

## 7. Derivation (`deriveControlView`)

Pure: same model, same view. Online selected amp → connected shape
(`AmpRef(id: ip, name: deviceName, model: modelName, ip, online, heard,
manual, silentFor)`, `power` from `powerPhaseAt(now)`, **masked** mute /
volume / source, enabled slots as `SourceItem`s, floor / ceiling). A
selection that is not online → the waiting shape (§6): `selectedAmp` is
that amp as last known, or a synthetic `heard: false` ref for a
never-heard IP; power Off, unmuted, no sources. No selection → the
not-connected shape. In both, **`volumeDb` is `null`** (3.9.4, checklist
5): "no reading" is the absence of a value, never a sentinel a clamp could
turn into "−15.0 dB"; the dial takes a `double?` and rests at its start.
`knownAmps` = **every** amp ever heard (the map never evicts, 3.9.0):
online ones first, then the silent ones with `silentFor` quantized (§3),
each group in numeric IP order, plus the never-heard selection last. Only
the selected amp's broadcasts reach the control fields; every broadcast
feeds the list (3.0.5).

## 8. Pending-command mask + confirmed channel (3.1.0)

| Field  | Pending slot      | Confirmed by (exact)        | Displayed             |
|--------|-------------------|-----------------------------|-----------------------|
| volume | `pendingVolumeDb` | `status.volumeDb` (0.5 dB grid, decode is exact) | `pending?.value ?? status` |
| mute   | `pendingMuted`    | `status.isMuted`            | same                  |
| power  | `pendingPower`    | `status.isPoweredOn`        | same (+ Booting overlay) |
| source | `pendingSource`   | `status.activeSourceIndex`  | same                  |
| post-boot hold | `pendingVolumeDb` armed with `(boot.target, confirmedAt + 1500 ms)`, re-armed from the send | `status.volumeDb == target` **only after the startup send went out** (the first On packet's pre-shutdown byte is never a confirmation — gotcha #8 watch-out #2) | the target; the −42 misreport is recorded, not shown |

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
pending slot synchronously**, then `await sink…`; on a throw, restore the
slot (rollback, checklist 3).

`selectSource` (3.8.0 / 3.8.1, KDE `selectSource()`): after the gate and
the enabled-slot bounds check, **one write** arms `pendingSource` and
`pendingVolumeDb` at `startupVolumeTarget` (the startup setting clamped
to the limits in force), then **one sink call** sends source×2 and
volume×2 with zero delay. Mute is untouched (3.7.1) and the boot record is
untouched. Inside a confirmed post-boot hold the volume slot *is* the
hold, so its existing deadline is kept when later than the 400 ms window
(a switch never shortens a hold) and the rollback restores the slot's
previous value instead of nulling it (nulling would drop the hold and
show −42). Not routed through `_writeVolume(userIntent: false)` on
purpose: that would be a second sink call after an `await`, a `send
volume` trace instead of `send source`, and a second write.

**Volume (3.6.x, 2026-09-22).** Every volume write goes through one
private `_writeVolume(ip, target, userIntent:)`; the target is already
on the 0.5 dB wire grid and clamped by `AmpState.clampDb`, the one
min/max clamp (idempotent). `stepVolume(direction)` is synchronous: it
steps `AmpState.stepDb` (the persisted step size, mirrored like the
range) from the *displayed* value so rapid taps accumulate, and returns
whether anything was written — a bound step sends nothing and returns
false, which ends a hold-to-repeat chain without the widget keeping a
copy of the volume (checklist 9); a bound press on a *muted* amp still
counts (it unmutes and re-asserts). `setVolumeDb` is the dial's release
value. **Auto-unmute (3.6.5):** a user write on a muted amp arms
`pendingMuted(false)` in the same synchronous write and sends `mute
off` *before* the volume, as two sends with separate rollbacks; a
correction (`userIntent: false`) cannot touch the mute slot (3.7.1).
**Inside a confirmed post-boot hold (3.6.4b)** a user write re-targets
the deferred startup send (while it has not gone out), sets
`BootInProgress.userSent` so a matching broadcast may release the hold
(`holdConfirmable = startupSent || userSent`), and restarts the 1500 ms
fallback from that send. The deferred startup send still goes out with
the re-targeted value even if the user's confirmation already released
the hold — a deliberate deviation from the widget (which would send the
configured default): a user send inside gotcha #9's window can be
dropped and the deferred send is the only recovery.

**Limit-change clamp (3.6.6, KDE `applyImmediateClamp`).**
`_applyLimitClamp` corrects the selected amp when its *displayed* value
is outside `[floor, ceiling]`: one `_writeVolume(userIntent: false)`
(mute untouched), nothing when in range, no timer retry. It runs in one
coalescing microtask (`_scheduleLimitClamp`) so several triggers in a
synchronous run produce one command at the final limits. Triggers: the
settings listener when floor or ceiling changed, and the `_afterWrite`
hook — called after **every** `state =` in the owner (ingest, tick,
`_arm` including rollbacks, selection, the seams) — on an eligibility
edge: `selected && online && On && boot == null` going false→true, or
the selected ip changing while eligible. "Power reaching On" is thus
"the boot record dropped": by then the amp sits at the startup target,
which `_runBootFollowUps` clamps to the limits in force at the send, so
the post-boot evaluation is a no-op and never races the amp's own
startup application (gotcha #9).

`togglePower` (3.2.0), gated on `powerCommandAllowed`: On → Off arms
`pendingPower(false)`, drops any boot record and sends; Off → On calls
`markBooting` (a `BootInProgress` with the clamped startup target) and
sends — no optimistic On, the amp's broadcast confirms it or the 20 s
deadline falls back to Off; Booting → no-op, so repeats don't extend; an Off
that is only optimistic (the amp still reports On) is cancelled without a
boot record, so a stale On cannot "confirm" a boot. `_runBootFollowUps`,
after every ingest and tick, sends the startup volume once per confirmed
boot at ≥ +500 ms (`startupSent` flipped before the await and the hold's
fallback restarted from the send), for the amp that was booted even if
the selection moved; a failed send drops record and hold, no retry. An Off→On observed on the *selected* amp that this
app did not initiate (the KDE widget, the remote, the front panel, or a
late On after the 20 s timeout) creates an already-confirmed record in
`AmpState.ingest` (3.2.5, owner decision 2026-09-20): same hold, same
send, no Booting presentation. Non-selected amps get nothing.

The sink is `DevialetClientCommandSink`: `setPower`, `sendStartupVolume`,
`setVolumeDb` (3.6.0), `setMute` (3.7.0) and `selectSource` (3.8.0, with
its `postSwitchDb`) are all real. `DevialetClient.selectSource` reads its
target IP once and sends both pairs to it, so a `deviceIp` retarget by
another sink call while the first pair is in flight cannot split them.

## 10. Seams

- 3.4.x (done 2026-09-20): the Settings screen (`lib/ui/settings/`) edits
  `settingsProvider` directly — **settings are effective immediately**,
  the Android/iOS convention; the KDE widget's draft → Apply/OK follows
  Plasma's dialog convention and the two deliberately differ. The amp
  owner mirrors limits and startup through its settings listener; the
  theme is consumed in `app.dart::wrap` (a `MediaQuery` brightness
  override so Cupertino follows too, `MaterialApp.themeMode` mirrored);
  persistence problems show as a note in the screen
  (`settingsWriteErrorProvider`, `HydratedSettings.storeUnavailable`).
  The wire ceiling is a **required** parameter (1.1.3) that
  `DevialetClientCommandSink` reads from the settings ceiling at send time.
  `restoreDefaults()` exists without a row (3.4.11 deferred).
- 3.5.1 (done 2026-09-21): every UI entry point is gated at the widget
  *and* through `commandsAllowed` / `powerCommandAllowed` in the owner —
  the enumeration is the table above `ControlViewState.commandsAllowed`.
  3.6 / 3.7 (done 2026-09-22): `setVolumeDb` / `setMute` flipped with
  their `send …` trace lines; 3.8 (done 2026-09-24): `selectSource`
  flipped the same way (§9, §15) and the sheets became owner-driven (§16).
  The VOL ± screen-reader tap is a separate entry point since 3.6.1 (it
  never sends a pointer) and is gated the same way.
- 3.9.5 (done 2026-09-24): `setModelName(ip, model)` is the one function
  every model name passes through — it ignores an IP never heard (the
  trust gate) and never clears or overwrites a name once set (§17,
  checklist 28). `seedSilent(ip)` / `seedSelection(ip, manual:)` are the
  3.9.0 / 3.9.3 seeding seams (never persisted).
- 3.10.x: `confirmedAmpStateProvider`.

## 11. Debug simulated amp (`lib/domain/debug/simulated_amp.dart`)

Opt-in (was the debug bar's job until 2026-09-23; now only the TEST-NET
routing in `main.dart` and tests): synthetic status packets for 192.0.2.22/.23/.24
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
200 ms tick against the injected clock. So a simulated "Booting" now
completes, the owner sends the startup volume to the sim, and the misreport
is held and corrected — the whole loop without hardware. "Not responding"
stops broadcasting and the view flips after the real 8 s. A source switch
moves the sim's slot after 100 ms and applies the forced post-switch
volume through the same path as any volume command (3.8.1); the sim has
no per-input volume memory, so the readout simply lands on the startup
target as it does on the real amp. The sim selects and sets the dial range
through the owner's seeding seams, so nothing it does reaches the
persisted settings; the user's choice returns on the next launch.

## 12. Testing

No socket, no wall clock: `FakeUdpTransport`, `FakeClock`, `ManualTicker`
via provider overrides (`test/ui/support/pump_control.dart::hermeticApp`).
Pure tests on `AmpState` / `deriveControlView`; owner tests through
`ProviderContainer.test` with recording/throwing sinks; the simulated amp
is pinned to the fixtures the widget state table already uses and driven
with `tick()`. Every protective mechanism has a counter-test proving the
positive assertion fails without it (checklist 20): the mask (`applyUnmasked`
shows the stale broadcast leaking), the hold (`applyUnheld` shows −42
leaking), the startup delay (an early volume command is dropped by the
simulated amp, as measured on the real one), the explicit-selection flag
(a store that drops it lets auto-select resurrect a "None"), the heal (an
inverted pair bound unhealed leaks into the view), the seeding seam
(the user intent, unlike the seam, lands in the store), and — 3.6.x, run
by hand on 2026-09-22 with each guard removed — the dot-pulse leg, the
`userSent` hold release, the clamp's microtask coalescing (two commands
without it), the clamp trigger from a rollback (missed by an ingest-only
diff), the mid-drag disable and the mid-hold disable. 3.8.x (2026-09-24,
scripted as temporary patches, each reverted): the retired select formula
restored (the 16/29 pins go red, the 6–15 loop stays green), the client
reading `deviceIp` per send (the retarget test), the rollback nulling the
volume slot (the boot hold is lost), the switch using `now + 400 ms`
inside a hold (the deadline test), the sheet write-back removed (every
user-dismissal test red, the owner-driven ones green), the power edge
removed (tests 6/7), the edge turned into a level check (the empty-state
sheet pops on connect), `activeSourceIndex` dropped from
`ControlViewState.==` (gotcha #4 reappears) and the sim not applying the
forced volume. 3.9.x (2026-09-24, the same way): "None" keyed on `!hasAmp`
(the 3.0.8 caveat back: two sheet tests red), `silentFor` unquantized
(the bucket-equality test and the simulator fixture red), the resolver
without its cache (the replay test), without its close rule (three
session tests), retrying per tick instead of per new IP, and without its
own trust gate (the replay is lost even though the owner's gate still
refuses the phantom amp — each gate has its own job), `setModelName`
without its never-clear guard, the model name not carried across
`ingest`, and the dot pulse test itself catching a real bug (a running
controller ignores a `duration` change: booting ↔ waiting must restart).
Every harness overrides `modelNameSourceProvider` with
`FakeModelNameSource`, so nothing binds 5353 under `flutter test`.

## 14. Settings (`lib/domain/settings/`)

- `app_settings.dart`: `AppSettings` (one typed object, 3.3.1), keys,
  defaults, `load(Map)` (typed read: a mistyped or unknown value is the
  default plus a repair; an int for a dB key is accepted), `healed()`.
- `settings_store.dart`: `SettingsStore` interface; `InMemorySettingsStore`
  (tests, and the fallback); `SharedPreferencesSettingsStore` (3.3.0:
  `SharedPreferences` on Android, `UserDefaults` on iOS) — the only file
  importing the plugin.
- `hydrated_settings.dart`: `hydrateSettings()` runs in `main()` before
  `runApp`: open → load → heal → write repairs back; an unopenable store
  falls back to defaults on an in-memory store with `storeUnavailable`
  set (Settings surfaces it as the persistence note; the debug bar's
  `PREFS OFF` chip went with the bar on 2026-09-23).
  `hydratedSettingsProvider` throws unless overridden (required injection).
- `settings_owner.dart`: `SettingsNotifier` — intents update state
  synchronously and persist the changed keys in a constraint-safe order
  (widen first when both limits move); refused writes return a reason;
  a failed write keeps the value, sets `lastWriteError` and records it in
  `settingsWriteErrorProvider` for the UI; `restoreDefaults` never touches
  the selection.

| key | type | default | rule |
|---|---|---|---|
| `volume_floor_db` | double | −50 | −96..0 |
| `volume_ceiling_db` | double | −10 | −96..0; `ceiling − floor ≥ 1`, else the pair heals to −40/−39 |
| `startup_volume_db` | double | −40 | −96..0; clamped to the limits at use, never rewritten |
| `volume_step_db` | double | 1.0 | 0.5 / 1 / 2 |
| `theme_mode` | string | system | system / dark / light |
| `selected_ip` | string | absent | non-empty; removed when the flag is false |
| `has_explicit_selection` | bool | false | "chose X" / "chose None" / "never chose" |

Each dB value is brought into range before the pair is judged (checklist
10). The settings ceiling default is −10 while `VolumeCodec` still clamps
the wire at −15 (until 3.4.7 / 1.1.3).

## 13. Checklist mapping

1 mask in the owner keyed on send time (§8) · 2 one owner, no view copies
(§3) · 3 synchronous write + rollback (§9) · 4 explicit-selection flag (§6)
· 5 no amp → `volumeDb == null`, never a sentinel (§7) · 6 gate from one predicate (§9) ·
7 confirmed channel + boot seam (§3, §10) · 8 every setting stored on
change, read back on open (§14) · 9 stateless intents, the owner writes
back (§14) · 10 widen-first writes and in-range-before-pair healing (§14)
· 12/13 re-derive from the whole status on every ingest (§4, §7) · 19
fakes against disposable containers, seeding never persists (§12, §6) ·
20 the counter-tests (§12) · 21 the S25 kill-and-relaunch script (TODO
3.3.4) · 26 a broken store looks broken (§14) · 27 TEST-NET fixtures (§11)
· 22 the debug trace next to a raw capture (§15) · 28 the mask, the
gate and the heal live in one function each (§8, §9, §14); the widget
gates are the pointer-layer belt on top (3.5.1); the sheet route's one
`whenComplete` is the write-back for every dismissal path (§16); the
client reads its target IP once per multi-send command (§9); the mDNS
trust gate and "resolved once" live in `setModelName` (§17) · 29 3.8.2's
brief said "both sheets"; the working widget closes only the source list
on the power edge, and that is what was built (§16); 3.9.5's brief said
"one continuous browse", the library is one-shot, so the adapter cycles
(§17) · 30 no `AppLifecycleState` policy exists yet; a browse session
opened just before backgrounding runs to its budget (TODO 4.1.0).

## 15. Debug trace (`lib/domain/amp_trace.dart`)

`ampTraceProvider` gives the owner and the real command sink an
`AmpTrace`: one line per event on the owner's monotonic clock,
`[amp] <ms>ms <event> k=v …`. The default is `AmpTrace.none`; `main.dart`
overrides it with `debugPrint` under `kDebugMode` (so it reads over
`adb logcat -s flutter`) and release builds trace nothing — every call
site checks `enabled` before doing any diffing. `lib/domain/` stays free
of Flutter imports because the emitter is injected.

What is traced, and where:

- `send power` / `send startupVolume` / `send volume db= ceiling=` /
  `send mute muted=` / `send source index= db= ceiling=` — inside the
  real methods of `DevialetClientCommandSink`, *before* the await, so the
  timestamp is the send instant (`send source` names the forced volume
  it sends in the same invocation); the simulated amp is never traced
  (the routing sink sits outside it). `send failed` from the owner's
  catch (checklist 17: a dead route, not a dropped packet).
- `clamp ip= from= to=` — the limit-change correction (3.6.6), just
  before its `send volume`.
- `rx power= raw= db= source=` — the selected amp's broadcast, only when
  power, the raw volume byte or the active source index changed
  (change-only keeps `debugPrint` throttling irrelevant).
- `boot booting` (`markBooting`), `boot confirmed` / `boot
  observed-external` / `boot timeout` and `hold released
  reason=confirmed|fallback sinceOnMs=` — diffed in the owner between
  the amp before and after `ingest` / `tick`. The release reason
  re-derives `PendingValue.isConfirmedBy` for reporting only;
  `resolvePending` stays the one implementation.
- `boot startup-send sinceOnMs=` — in `_runBootFollowUps`, the app-side
  offset a live report needs.
- `view power= db= muted= hasAmp= source=` — after every state write
  (`_arm`, `ingest`, `tick`, selection), when the *displayed* values
  changed: what the dial showed, from the same derivation the UI renders.
  A held −42 therefore never produces a `view` line, which the owner
  tests pin.
- `sheet kind=none|amp|source [reason=power]` — the owner's sheet slot
  changed (§16), so a dismissal path that forgot to write back would show
  as a missing `kind=none` in a live log.
- `mdns session open reason=start|new-ip` / `mdns session close
  reason=resolved|budget|dispose`, `mdns hit host= ip= known=` (first
  time per IP), `mdns applied ip= model=`, `mdns unavailable error=`
  (once per session attempt) — the resolver (§17); `model ip= model=` —
  the owner accepted a name. `applied − rx` for an IP is the number a
  live report measures.

Tests capture lines through a provider override
(`amp_state_owner_test.dart`, `traced: true`); the format and the
"real sends only" rule are pinned in `amp_trace_test.dart`. First used
for `docs/protocol-verification-2026-09-21-boot.md` (Task 3.5.2).

## 16. Sheet visibility (Task 3.8.2 / 3.0.6)

`AmpState.visibleSheet` (`SheetKind { none, amp, source }`) is the one
slot that says which sheet is visible — cross-view state with exactly one
owner (checklist 2), expressed as *what is visible* rather than as a
route so the two-pane layout (3.11.x) can render it as a pane. Transient,
never persisted. One slot means the two sheets are mutually exclusive by
construction; there is no "close the other one" code.

- **Open:** the device card and the source trigger call `openSheet(kind)`
  (their widget gates are unchanged). `openSheet` is *not* gated on
  `commandsAllowed`: the source sheet's empty state is reachable with no
  amp, and the rows carry their own gate (3.5.1).
- **Route:** `ControlScreen` listens to the slot (`ref.listenManual` with
  `select`) and pushes the matching `showAdaptiveSheet` when it leaves
  `none`. The route's completion future fires on **every** pop, whatever
  caused it — hardware back / predictive back (`popRoute`), a barrier
  tap, the Material drag-down, a row's own `Navigator.pop`, the sheet
  popping itself — and its one `whenComplete` writes `closeSheet(kind)`
  back. That is the structural guarantee (checklist 28); its boundary is
  a sheet pushed by any *other* function, which would not be covered.
- **Self-pop:** each sheet calls `popWhenSlotLeaves(ref, context, mine)`
  (`lib/ui/platform/sheet_self_pop.dart`): when the slot stops naming it,
  the sheet pops its route if current, or removes it in place if it is
  still active but already covered (the screen pushed the other sheet in
  the same notification, before this listener ran). Both complete the
  route's future. A route already on its way out is neither current nor
  active and is left alone, so the write-back can never double-pop.
- **Power edge:** `_afterWrite` keeps an edge key next to the clamp's —
  "selected amp reachable and On". On a true → false transition with the
  **source** sheet visible, the owner writes `none` (trace `sheet
  kind=none reason=power`). An edge, not a level: a sheet opened with no
  amp must survive the connect that follows. The **amp sheet is not on
  the edge** — it stays open through a power change so an amp can be
  switched while one is off. This is the KDE widget's rule
  (`onPowerStateChanged` closes `sourceListOpen` only); 3.8.2's brief said
  "both sheets" and was corrected against the working implementation
  (checklist 29, owner decision 2026-09-24). It supersedes the 3.5.1 note
  that the source sheet stayed open with dimmed rows through a power
  change; the row gate itself remains for a sheet opened while the amp
  is already Off.
- **Screen left:** on compact width a sheet is modal, so "reset when the
  screen is left" reduces to `ControlScreen.dispose` writing `none`. The
  Cupertino popup has no swipe-to-dismiss (barrier tap only), so the iOS
  dismissal paths are barrier, back key, row pop and owner pop.
- **Tests:** `sheets_test.dart`, group "sheet visibility is owner-driven":
  one test per dismissal path asserting the slot reads `none` afterwards,
  the power edge for both non-On phases with the amp-sheet counter-half,
  the empty-state sheet surviving a connect, the swap, and teardown with a
  sheet up. Counter-runs in §12.

## 17. mDNS model name (Task 3.9.5)

`docs/protocol.md`, "mDNS model-name resolution", is the spec; measured
on the real amp on 2026-09-24: instance "My Devialet", SRV host
`Expert140Pro-K48A00904ZE1V.local`, A 192.168.0.22, port 80, TXT
`CPath=/spotifyconnect/zeroconf`. The **SRV host name** is what
`parseModelName` consumes; the instance name is the friendly name.

```
lib/networking/model_name.dart                     parseModelName (pure; KDE model_name.rs + a .local strip)
lib/networking/model_name_source.dart              ModelNameHit, ModelNameSource, MulticastLock (+ Noop*)
lib/networking/multicast_dns_model_name_source.dart the multicast_dns adapter (Android, desktop)
lib/platform/android_multicast_lock.dart           WifiManager.MulticastLock over a MethodChannel
lib/platform/bonjour_model_name_source.dart        iOS: an EventChannel fed by NetServiceBrowser (Swift)
lib/domain/model_name_resolver.dart                ModelNameResolver + modelNameSourceProvider
```

- **Seam.** `ModelNameSource.browse()` yields `(hostname, ip)` strings;
  subscribe = start, cancel = stop; a stream *error* means "cannot run at
  all" and is terminal. `main.dart` installs the platform source by real
  OS (`multicast_dns` behind the lock on Android, `multicast_dns` without
  a lock on desktop, Bonjour on iOS — pure-Dart multicast would need
  Apple's multicast entitlement there); tests get `FakeModelNameSource`.
- **Adapter.** `multicast_dns` is one-shot: `lookup()` answers from its
  cache without sending when the cache is live, and each packet replaces
  the cached list. So a session is a loop of **cycles** — fresh client,
  `start()` on IPv4-capable interfaces only, PTR → SRV → first IPv4 A,
  `stop()` — every `kMdnsQueryInterval` (2 s), each lookup waiting
  `kMdnsLookupWindow` (1 s). A `start()` failure is the terminal error;
  a later exception is that cycle's alone. The lock is held from listen
  to cancel. Both constants are guesses until the S25 run records them.
- **Resolver** (owned by `AmpStateOwner` like its sink and trace). Every
  hit is cached for the process lifetime and applied only for an IP the
  owner has heard over UDP — the resolver's gate keeps a cached hit
  unsettled until its amp exists, the owner's `setModelName` refuses to
  create one (the C4 counter-run shows they do different jobs). A hit
  that lands before the first UDP packet is replayed from the cache in
  the same `ingest`. Settled = applied, or parsed to nothing; never
  re-attempted. Sessions: one opens on `start()`; it closes when every
  known IP is settled and at least one hit was heard, or at
  `kMdnsSessionBudget` (60 s) on the owner's tick; a new unresolved IP
  opens a fresh one. A source error traces one `mdns unavailable` and
  closes; the next *new* IP may retry once (bounded by distinct IPs).
  The amp keeps its UDP name and the sheet says "· name unresolved"
  (checklist 26).
- **Display.** `AmpRef.displayName` = `model ?? name` (the IP when
  neither), `AmpRef.name` stays the UDP name for the subtitle; `TrackedAmp.
  modelName` is carried across every `ingest`.
- **Permissions.** Android: `INTERNET` (the main manifest had none — no
  release build had a socket before 3.9.x) and
  `CHANGE_WIFI_MULTICAST_STATE`. iOS: `NSBonjourServices`
  (`_spotify-connect._tcp`) and `NSLocalNetworkUsageDescription`; the
  permission flow is 4.0.0 and the Bonjour source is unverified until the
  iPad session (4.0.x).
