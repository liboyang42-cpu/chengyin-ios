# Creator-local reaction rehearsal (P036, feature 29)

Base 077273784d7fed5397f84f17b2a659723f3f3b22 plus sealed 25 → 26 → 27 → 28, in that order. This closes the `react` author-renderer gap in the feature 26 catalogue audit. It does not claim any other remaining category or a full-screen pixel-identical Mini interface.

## Source and configuration

Private Mini commit 95e499471eaa39c28f77d16125f0cc17b8c37123:
- pages/play/components/playkit-reaction/index.js blob 4fd8e69eeea3125bba73d7d381cd4923a624fb49
- index.wxml blob d7a4a6a9dcf6b7989e58711d2fd27d50b8c8d107
- advanced-game-preview.js blob 40156f8c3f7d12d69d0b301fa397d5a8f967ec2a
- node-game-catalog.js blob 22ca448703f05b9c846129f02614c74b29ad16a6
- advanced-game-config.js blob 3637e13fd0f06cb645bb8f09ac208ead5a9a701a

Read kicker (source trim, <=32 UTF16 units), integer rounds 1...10, goalMs 120...2000. The source validator caps goalMs at 2000 while the existing native validator and source relax helper permit 3000. Only this new rehearsal uses the intersection; existing validation is unchanged. Values 2001...3000 display an unavailable explanation, never silently clamp or change the draft. This old interface difference is reported to the root for separate ownership.

Current-config mode inspects even a disabled configured section. Sample mode copies only the real DEMO kicker “屏幕一变色就点” when its exact encoded field still equals the default, and enables only the temporary copy. Custom, whitespace, missing, unknown and sibling data stay intact. Missing title uses the actual builder fallback “变绿就点”; absent/invalid numeric configuration is unavailable. This is pristine-value comparison, not edit-history tracking. Other games are never disabled or copied back.

## Local run

No 3-2-1 countdown. Tap to wait a locally randomized round(1400 + unit * 2800) milliseconds, then see an explicit “Tap!” signal with a green tint. Waiting and signal have text, not color alone. A waiting tap is early even if the nominal timer deadline passed but the signal callback has not run. A signal tap below 120ms is also early. Neither consumes an accepted round or erases earlier accepted readings; retries are unlimited. After the configured number of accepted rounds, show the minimum reading and local comparison best <= goalMs. Early taps do not invalidate the whole run: this follows actual source methods, rather than a contradictory source comment. The native subtitle uses the configured count rather than Mini's hard-coded three-round prose. Done ignores stage taps; Reset clears the local run; Close returns.

These are author-local readings, not verified player scores, server verdicts, rewards or task completion. Randomness controls only signal delay, never a fabricated result. No server start/submit/verdict calls or haptics. Normal color updates have no motion animation.

## Clock and interruption fences

Reuse feature 28's TemplateTimerRehearsalScheduler, TemplateTimerSystemScheduler and TemplateTimerCancellation without modifying that sealed file. Inject the monotonic millisecond clock (default integer-floor system uptime), random-unit delay and scheduler. Wrap its repeating timer as a cancellable single-shot. A premature callback re-arms the remaining delay; a late callback anchors reaction time at the actual signal callback, not the deadline. This does not measure physical display latency, and that UI behavior has NOT_RUN acceptance.

Separate action and wait generations reject queued cancelled ticks and stale taps/reset/close before considering the current draft lease. A stale callback cannot retire a newer run. Signal transition also invalidates old waiting tap closures. The lease includes owner, account session, draft identity, exact encoded draft, metadata/media generations, busy/review locks. Every model publication retires; nonfinite/backward/overflow clock or invalid random unit aborts without a reading and requires Reset. Weak callback captures avoid retaining a closed controller.

Close, navigation disappearance, any nonactive scene and edits retire the entire local run and cancel its wait. Foreground/reentry reloads a fresh run. This is deliberately stricter than Mini hide (which retains earlier accepted times); no result from before leaving can revive after returning. This feature does not repair a source queued-callback weakness or modify 28's timer lifecycle.

## Verification and integration

40 native tests are authored: 20 Core, 20 App controller. All are NOT_RUN in this environment. Static contract checks, Tree-sitter parsing and an actual-source Node VM harness are separate evidence, not Swift type checking or native test results. Swift/Xcode, Combine scheduling, visual taps/display timing, scene lifecycle and VoiceOver execution are NOT_RUN. The source VM uses inert stage/haptic/timeout mocks and tests source methods, not native controller execution.

Add the two source leaves, two XCTest leaves and bilingual localization fragment centrally during integration. The registration fragment lists these only; Package.swift, PBX, public strings and permissions are unchanged. The Core sample snapshot and shared scheduler require 25 and 28 respectively; preserve intervening 26/27 and all previous host hunks. Two lines add the current-config navigation; four lines add the source-sample section. All private original modules and harness artifacts remain outside the public product patch.
