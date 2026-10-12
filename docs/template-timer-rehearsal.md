# P036 grouped creator-local timer rehearsal (batch 28)

## Complete grouped flow
Countdown and blind stopwatch share one Core state machine and one App clock/lifecycle controller. Current-configuration entries live next to the respective fields. The sample browser offers both kinds with real source DEMO fields, only in an isolated copy. The old coin and all25/26 samples remain unchanged.

Countdown reads kicker, seconds and doneText. Start/restart, absolute-time remaining seconds (ceil), rounded/clamped progress and doneText at expiry follow Mini. There is no countdown pause or manual-stop capability in source; neither is invented here. Reset/close are author controls.

Stopwatch reads kicker, targetSeconds, toleranceMs and tries. Start begins on the local button immediately (the shared Mini stage3-2-1 animation is not reproduced). The elapsed reading hides at1000ms; target/tolerance stay visible. Pause freezes elapsed time without unmasking it. Resume excludes paused duration. Stop while paused is rejected. Stop produces only a local readout: elapsed/deviation, early/exact/late and source-style excellent/within-tolerance/missed tiers. Misses consume configured local allowance;0 means unlimited. After a match or exhaustion, explicit reset begins a new author rehearsal. Beyond target+30s the round aborts without consuming a miss.

The live Mini delegates tries and verdicts to its shared stage/server. This local state machine mirrors only author inspection of allowance and readout. It sends no start/submit/finish event, evidence, gameplay outcome, reward, microphone or location request. No player stage success/failure is invoked. No generic timer-modifier or other unimplemented category is counted complete.

## Configuration boundary
Selected timing fields are validated locally against existing source/native ranges: countdown5...3600s, nonblank doneText<=60 UTF-16; stopwatch target3...120s, tolerance50...5000ms, integer tries0...10; title<=32. Disabled games can be inspected without enabling the real draft. Current mode seeds nothing. Invalid or missing required data remains unavailable rather than being invented or repaired.

Real source examples exist: countdown kicker/doneText and stopwatch kicker. Only whole fields currently byte-equal to native defaults receive those values in the copy; current numeric target values are preserved and always shown. The literal source stopwatch sample title mentions10 seconds even if the author configured another target; UI labels explicitly identify the actual configured target and sample-copy boundary. Changed/missing/whitespace/unknown/sibling data and raw numeric strings remain intact. Reset-to-default is eligible like Mini; no edit history is inferred. Exact source trim is reused. No old validator is modified.

## Clock and lifecycle
The default clock is monotonic systemUptime in milliseconds, injected as a closure. The scheduler is injected independently and uses Combine main-run-loop timer subscriptions:1s countdown/50ms stopwatch. Elapsed time is derived from the current clock minus anchor plus paused accumulator, not by counting ticks. Nonfinite/backward clocks abort the local round.

Tick generation is separate from user-action generation. Cancelled but already-enqueued ticks are rejected before checking a newer lease, so they cannot retire or alter a fresh run. Start/pause/resume/stop/reset refresh action and tick identities; tick completion/timeout retires scheduling. Configuration, metadata/media, owner/session/identity, exact draft, busy/review, close/leave and background fence all state. Both kinds retire on background as requested; returning starts fresh rather than continuing Mini countdown background timing. Old actions, reset, close and ticks cannot cross a reload or ABA change. Subscription ownership uses cancellable cleanup and callbacks capture the controller weakly.

## Source and scope
Pinned private source commit95e499471eaa39c28f77d16125f0cc17b8c37123. Component countdown JS e03b4e3260403e015d6ea19387b6e90874883195; stopwatch JS87f8029d8c0bf5a6ba98b5ab898cddb1e66f88ff; exact WXML and original formatElapsed are recorded in the delivery. Private originals stay outside product patch. The original-component harness uses fake Date/intervals, inert haptic/stage mocks and the actual formatter; it is not wx/native execution and does not prove native callback fences.

Base077273784d7fed5397f84f17b2a659723f3f3b22 plus sealed25→26→27. Two exact+2line config hunks and one+6line browser section; merge hunks without replacing cumulative hosts.2source leaves,2XCTest and33 bilingual strings are supplied as registration fragments, with no public registry edits.

## Verification limits
20 Core and16 App XCTest cases are authored, NOT_RUN without Swift/Xcode. App cases inject clocks and deliberately fire cancelled callbacks across pause/reset/reload/background/owner/ABA/close. Static checks and Tree-sitter parsing are not native typechecking, Apple compilation, timing measurements, App UI, actual Combine scheduling, navigation, VoiceOver, simulator/device or production/persistence verification.
