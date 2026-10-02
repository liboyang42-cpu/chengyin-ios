# Native PlayKit screens: source-backed implementation, not acceptance

## Bounded scope

This packet replaces generic controls with genuine native task bodies for the 22 dedicated Flutter PlayKit screens and adds five newer mini-program-only kinds: sort, match, classify, compass and shout. The server `steps` segment uses the walking progress UI; it is not counted as another migrated full-screen page. This is implementation coverage within that set, not a claim that the application, every source page, every advanced segment or any live business flow is complete.

Forms use native navigation, visible labels, keyboard-aware inputs, per-item pickers and accessible reorder buttons. Timed/sensor games use focused content within the same navigation stack. `PlayKitInlineHost` renders the real task body without a nested list, scroller or navigation container for story flows. No Flutter fullscreen/nested routing is copied mechanically. Unsaved input, hardware streams and running local attempts are discarded on explicit navigation; the native host asks before leaving dirty content. The story host can receive `reportDirty` for its own navigation guard.

## Covered interactions

- Questions: typed, single-choice, newer multi-choice `optionIds`, and photo evidence
- Branches: server-supplied current options only; no client next-node logic
- Estimate: finite, range-checked number; price-pair: server item IDs; hidden objects: rendered-image-relative hit position with explicit review, no hidden answer coordinates
- Profile: server question keys, required answers, pick IDs and separate avatar upload; note: presets, length, prior messages and audience disclosure
- Prediction: chosen answer, pending/revealed/voided states; draw/coin/dice: server results, never local random outcomes
- Reaction: randomized 1.4–4.2 second cues, false starts and 120 ms floor, actual presented-cue timing, all measured rounds
- Countdown, blind stopwatch and typing: monotonic measured clocks, acknowledged START before timing, interruption invalidation, exact source payloads; local numbers are measurements, not pass/reward decisions
- Ball: calibrated real device tilt and wall contacts; quiet: calibrated scalar audio peaks, not motion stillness; compass: continuous accurate bearing hold without START; shout: acknowledged START and continuously loud hold reset by silence
- Bingo: service `filledPositions`, `cellSpecs` and line-progress readback, without local tile toggles or a made-up claim action
- Walk: actual server `todaySteps`, merchant-locked goal and explicit encrypted-proof block
- Sort/match/classify: complete permutation, one-to-one pair lists and complete item-to-bin maps. Only server overall verdicts are shown

## Action and evidence boundaries

`PlayKitActionReview` freezes session ID, server version, account/namespace/epoch owner, action, canonical payload and idempotency key. A version/account change invalidates the review. Unknown outcomes preserve the frozen request; reading a higher version alone does not prove that request succeeded. Existing exact retry/reconciliation remains the only recovery path. All task outcomes, completion and rewards come from the returned server state.

Photo evidence is scoped to session, kind and exact version. Capture, explicit upload consent and task submission are distinct. Only an uploaded HTTPS URL enters the action. A 10 MB PlayKit limit is enforced before upload. Upload failure is distinct from an uploaded-but-unsubmitted state. Profile avatars upload without automatically registering the profile. Degraded photo-model responses do not become a local pass/fail verdict.

All network capabilities, hardware grants, production factories and media hosts remain off by default. `PlayKitNativeSensorProvider` exists for an independently accepted configuration. It checks purpose keys, explicit gesture and OS permission; audio buffers are inspected in place and only scalar peaks escape, with no recordings or uploads. Sensors stop on background, interruption, dismissal, session/version change and stream failure. Freshness/accuracy limits are intentionally conservative and still require physical-device acceptance.

## Source proof (derived contracts; no private implementation copied)

Flutter baseline: `a63e9e91c82a3282e8dd7138f943b1a8cbfc021d`.

- `lib/feature/play/advanced/playkit_fullscreen.dart`: 22 dedicated-screen registration
- `lib/feature/play/advanced/playkit_host.dart`: kind-scoped server actions, version/session identity, photo upload then submit
- `lib/feature/play/advanced/fullscreen/playkit_quiz_data.dart`: question modes, option IDs, estimate value, image-relative ratios
- `lib/feature/play/advanced/fullscreen/playkit_prefab_data.dart`: profile/photo/note/type contracts and degraded photo result
- `lib/feature/play/advanced/fullscreen/playkit_fullscreen_payload.dart`: reaction roundsMs and quiet heldMs conversion
- `lib/feature/play/advanced/fullscreen/playkit_fullscreen_logic.dart`: reaction, ball and quiet sampling/calibration semantics
- `lib/feature/play/advanced/fullscreen/playkit_countdown_view.dart`, `playkit_stopwatch_view.dart`, `reaction_view.dart`: START, timing and interruption contracts

Read-only mini-program snapshot: `fad4d6bd7e3c3e501441fe19c8de9a9cd78230fc` (relevant paths unchanged at reviewed later head).

- `pages/play/utils/playkit-view.js`: lines 18–87 priorities/type mapping; 166–230 completion; 437–468 QA multi; 621–653 sort/match/classify projection; 711–778 compass/shout/bingo projection; 819–843 actions; 904–942 payload shapes
- `pages/play/components/playkit-{sort,match,classify}/index.js`: native-equivalent player interactions and overall-only verdict
- `pages/play/components/playkit-{compass,shout}/index.js`: real heading/audio measurement and lifecycle
- `pages/play/utils/play-audio-level.js`: percentile baseline and scalar-peak thresholds

Important divergences resolved: Flutter incorrectly treated bingo as local/empty, lacks five server-backed kinds and QA multi-select, and has a weaker walk placeholder. Native uses the newer source business contracts while keeping native presentation independent. Platform-specific `SUBSCRIBE_TIME_WINDOW` is not enabled or imitated.

## Explicit remaining work

- Apple compilation, XCTest execution, UI tests, actual screenshots, Dynamic Type/VoiceOver and visual acceptance are NOT_RUN in this Linux workspace
- No live backend, production account, signing, sensor permission or physical-device acceptance has occurred
- WeChat encrypted step proof has no approved native alternative; the genuine progress screen cannot submit a native pedometer number as equivalent proof
- Scan overlay/AR reply rendering and in-camera photo framing overlays remain gated; text/image/approved audio paths and honest notices are present
- Media hosts and audio/sensor factories need independent approval/configuration. A configured endpoint is not evidence of deployed acceptance
- Existing advanced segments outside the dedicated screen set (for example blindTaste, diyName, silentOrder, slowTask, musicCorner and timeWindow), plus separate gameTimer/stickerBook sheets, are not declared covered by this packet
- New mini-program game authoring/configurator UI is outside this player-runtime packet

See `playkit-screen-verification.json` for authored-vs-executed evidence. Python checks are source/schema checks, not a Swift compiler or proof of a working device flow.
