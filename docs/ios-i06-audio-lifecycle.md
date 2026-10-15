# CY-HANDOFF: IOS — I06 native playback lifecycle isolation

2026-10-15 UTC. **SOURCE_CANDIDATE / EXECUTION_NOT_RUN / NOT_PUSHED**. This is a bounded native playback fix, not acceptance of the whole I06 card.

## Identity and scope

- Repository/branch: `liboyang42-cpu/chengyin-ios:migration/native-ios`.
- Exact published parent: `80c16907ba160e41ecf28402ab7f433dc12e9e0b`, tree `7d4e97c624edf46eb34743db4d634ee7d5dc8a10`. All 5,080 tracked file blobs in the isolated candidate's starting snapshot were matched against that remote tree before editing. No old unsubmitted implementation was imported.
- Read before selection: native `ios-current-status.md`, README, existing audio driver/coordinator/view/session-owner paths, and backend `IOS_START_PROMPT.md`, `IOS_HANDOFF.md`, `BACKEND_CHANGES.md`, `COORDINATION.md`, `OWNERSHIP.md`, and `TASKS.md` at control `e7fe5d00451bf71a85df763f73df0eca5d19e32c`.
- I06 is independently native. **BK dependency: none; NO_API_CHANGE.** The control record's frozen backend candidate remains `1e403b135206844a34219753a36e2dee39c7dd59`, with follow-up candidate `4a943501262cb533158428d9748d8ac49aaa8950`. Neither is used to invent a new audio API or deployment. `TEST_DEPLOYED=NO`; **AI-VOICE remains DRAFT**. No backend or shared control file is changed.
- No applicable `AGENTS.md` or local `.agents/skills/*/SKILL.md` was present in this snapshot or its applicable ancestors. Engineering/README guidance was read. Current user instructions defer all tests, builds, app execution, and CI checks.

## Source-confirmed gap and sanitized reproduction

The existing path is an explicitly injected, consented `PlatformAudioPlayback` consumer -> approved-origin bounded download -> native `.playback` / `.spokenAudio` session -> `AVAudioPlayer`. Ordinary app composition still supplies no native driver factory.

The baseline registered four notification observers for the driver's entire lifetime. Each observer scheduled an unbound main-actor task that later read the driver's current callback and stopped its current resources. There were two confirmed control-flow defects:

1. Starting audio sets the session category. A resulting `categoryChange` notification was treated exactly like an interruption, so the player's own setup could stop the run it had just started. This is a possible source path, not a claim that every `setCategory` call emits a notification on every device.
2. A notification received for run A could remain queued while A was replaced by run B. Its task then captured B's callback, stopped B, and delivered `.interrupted` to B. The coordinator's existing generation guard could not reject this, because the driver supplied B's callback.

Synthetic reproduction: select `https://audio.example.test/one.mp3`, approve and start; queue an interruption or compatible category-change notification; select and approve `two.mp3` before draining queued work. The old notification must not stop the second source. No real URL, account, audio service, microphone, or media byte fixture is accessed.

An additional resource consequence of the same lifetime-wide handling was that idle/select/double-stop paths always deactivated the shared audio session, even when this driver had never activated it.

## Implementation and natural recovery

- `App/NativePlatformAdapters.swift` retains the existing download restrictions, AVAudioPlayer and AVAudioSession operations. It adds internal dependency seams for isolated regression authorship; production defaults use the same native APIs and deferred main-actor delivery.
- Each valid start registers observers with that run's immutable generation, **captured at registration before any queue hop**. Stop increments generation and removes the observers before cancelling download/player/session resources. Already queued delivery from a retired registration rejects before reading the current callback.
- A category-change notification is ignored only while the current session still has the expected `.playback` / `.spokenAudio` configuration. An incompatible category takeover still stops playback. Other route reasons retain the baseline conservative stop behavior; this change does not broaden routing policy for headphone insertion or output override.
- Interruption-ended, including `shouldResume`, neither restarts playback nor stops a newly explicit retry. Began, malformed interruption data, background, media-services reset and remaining route-change reasons still terminate the current run.
- Terminal error, completion and interruption capture the callback, stop/release resources, then deliver the result. Cleanup cannot run after a callback starts a replacement. Repeated stop only deactivates when this driver recorded a successful activation, preventing idle or double-stop from deactivating an unowned session.
- The existing coordinator remains unchanged: explicit pause/resume is retained; interruptions return to idle; failed/ended media can be explicitly retried; source/scope changes invalidate old callbacks; suspend/dispose clear consent. Existing view review, inactive-scene suspension, disappearance disposal, and session-owner teardown remain in place.

This is not a shared multi-consumer session arbiter. The activation flag prevents this driver's idle/double-stop interference; it does not establish exclusive ownership if another native audio subsystem takes over the same session concurrently. Those interactions still require device evidence. Existing view/owner teardown is still required; no background-audio entitlement, deployment target, microphone access, provider contract, recording flow, or new autoplay behavior is added.

## Authored acceptance and actual evidence

Ten AppUnit regression methods are added to the existing, already wired `Tests/AppUnitTests/NativePlatformAppTests.swift`. They use the real driver and coordinator, synthetic downloader/player/session operations, a private notification center, and an explicitly drained queue. No test sleeps or real HTTP/audio session calls are needed. Vectors include:

- Own category-change during activation; successful playback and explicit pause/resume.
- A's queued interruption delivered after B is selected; B remains playing.
- Idle and loading cleanup without deactivating an unowned session; late download rejection.
- Background, output loss, and media reset in loading/playing/paused states; duplicate queued events and late completions.
- Ended/shouldResume while paused, after an interruption, and after a fresh explicit retry; no automatic restart.
- Incompatible category takeover and missing reason/type data.
- Download, activation, player decode/init, preparation, play and resume failures; cleanup and explicit retry.
- Disposed pending work, reentrant retry from a terminal callback, dormant capability and unapproved-origin denial.

Three additional Core regression methods in existing `Tests/CoreTests/PlatformConsumerTests.swift` preserve interrupted-run callback fencing, renewed approval after suspend/dispose, and same-URL replacement under a new scope. No production Core change or Xcode project regeneration is required. These **13 methods are authored, not executed or passed**.

The AppUnit stubs do not execute actual `AVAudioPlayer` delegate completion/decode-error delivery. Those terminal callbacks remain source-reviewed, player-identity-fenced paths; the failure vectors above exercise download/setup/preparation/play/resume errors, not a real codec or speaker.

Performed: source reading, manual call-flow review, direct remote source/blob identity comparison, diff/byte inspection, and bounded artifact hash generation. **NOT_RUN:** Swift/Core XCTest, AppUnit, XCUITest, typecheck, Xcode/build, simulator/device, accessibility, Python/Node/Java suites, lint, CI lookup/dispatch, real networking/accounts/audio, lock-screen/route hardware validation, backend integration, deployment, signing or release. No capability was enabled, and no push/commit/merge was performed by the implementation worker.

Real-device call interruption, headphone/Bluetooth transitions, lock screen, foreground/background UI, teardown under memory pressure, other simultaneous native audio consumers, and observer/session leak checks remain unverified. Source review cannot sign off these device acceptance conditions or the entire I06 card.

## Sources and rollback

- [Backend control read for this slice](https://github.com/liboyang42-cpu/hengyin/blob/e7fe5d00451bf71a85df763f73df0eca5d19e32c/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md)
- [I06 ownership and requirements](https://github.com/liboyang42-cpu/hengyin/blob/e7fe5d00451bf71a85df763f73df0eca5d19e32c/docs/plans/mini-codex-cloud-20261015/IOS_HANDOFF.md)
- [Published native baseline](https://github.com/liboyang42-cpu/chengyin-ios/tree/80c16907ba160e41ecf28402ab7f433dc12e9e0b)
- [Apple route-change reasons](https://developer.apple.com/documentation/avfaudio/avaudiosession/routechangereason)
- [Apple interruption semantics](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioInterruptions/HandlingAudioInterruptions.html)
- [Apple route handling](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/HandlingAudioHardwareRouteChanges/HandlingAudioHardwareRouteChanges.html)

Rollback is limited to this slice's single implementation file, two existing regression files, and two iOS documentation paths. No persisted format, backend API, request identity, source-selection UI, artwork, merchant filtering, roaming, or localization delta is included.
