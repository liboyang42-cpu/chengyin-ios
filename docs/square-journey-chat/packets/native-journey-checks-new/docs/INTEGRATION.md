# JourneyChecks and ambient content packet

Isolated package. Do not replace shared AppSession, PlayExperienceView or PlayContracts with validation-host copies. No shared checkout was edited by this packet. No production capability, network, GPS, roll, cost or collection was exercised.

## Integrate

1. Copy Core/*.swift, App/*.swift and Tests/{CoreTests,AppUITests}/*.swift into matching native folders. The package reuses existing PlayWireValue, PlayExperienceSession, PlayExperienceService.request, HTTPTransport, multipart AuthRequestBuilder and error types. Do not add duplicate primitives.
2. Run `python native-journey-checks-new/tools/apply_host_hooks.py /explicit/native/root` after coordinating with the normal Play device/game/photo owner. The script adds a distinct JourneyCheck factory, optional node check consumer, ambient overview consumer, loss-tolerant eggs projection on PlayNodesResult, debug fixture route and merged bilingual default catalog. Anchor drift fails rather than overwriting another owner's work. It was executed only against validation-host copies.
3. The AppSession snippet stays inside AppSession because it needs its private identity/region/vault helpers. It uses the existing protected templateAuthoringSecureStorage primitive via closures for durable seen-state and write-ahead check locks. Keys are independently prefixed and include account, operational region namespace, session type/id, and (for checks) topic/node. No credentials or server narrative are persisted.
4. Run native tools/generate_project.py, tools/check_scaffold.py and normal source/host audit after merging. Run `swift test` and the authored JourneyContent XCUITest flows on the approved Apple SDK. None were available/run in this Linux packet.
5. Production factory has all three capabilities false: readsEnabled, checksEnabled, collectEnabled. Enabling transport flags is not account permission, cost approval or GPS consent. Approved endpoint/provider/session/legal/product acceptance remain external gates.

## Runtime integration details

- A node opening performs one optional encounter probe. Failed/unsupported probe is silent and never blocks answer, navigation, task completion or exit. Only encounter.allowedActions containing `check` with a nonempty checkId creates UI; no playKit or local prefab die creates a server outcome.
- Immutable review displays the action and any known reroll/settle consequences. Reroll is only available for an unsettled, not-rerolled receipt with positive known luck. Source says reroll spends one luck. Other impact/cost/narrative comes only from the server receipt, with settlement text/cost hidden until settled. Missing health/luck/DC/total remain missing.
- All mutations use exactly multipart topicId/nodeId/checkId. Business error text is preserved even at HTTP 200. An already-settled roll rejection may read the same settled receipt through the source-idempotent settle action. There is no new receipt API.
- Lost/cancelled/malformed mutation response preserves the write-ahead unknown lock through close/reopen/relaunch. Only a separately reviewed exact settle recovery is offered; it explicitly says it can also settle an unsettled check. Another check ID or unreadable journal stays locked. Definite business rejection clears a new operation's lock, but never clears an existing uncertain recovery lock. Session/epoch/region changes discard stale UI/replies; durable locks remain scoped to the original owner.
- Nodes' eggs are projected independently and loss-tolerantly so malformed ambient content cannot invalidate the main nodes response. Radius default/clamp 120m / 1...1000 and coordinate/text checks follow Flutter. Seen state does not claim collection success.
- Ambient accepts injected positions directly or via JourneyAmbientLocationSource; native view defaults source=nil. A host with an already-consented location owner may supply its bounded stream and must cancel when the journey is not visible. This packet does not create a CLLocationManager or request a permission. Position coordinates are not uploaded by these endpoints.
- Invoke `navigationProgress(nodeID:fraction:now:)` from the active navigation owner with measured progress, not fabricated location. It follows source one-shot 50%/90% companion milestones and newest-request fencing. A missing/failed line yields no empty placeholder. This package deliberately does not invent or enable a new navigation provider.
- Egg discovery cooldown is 180 seconds; bubble is 6 seconds. Companion display is 3.5 seconds. Native tick only clears text. Location/storage/companion/collection failure never blocks main task. Collect sends optional positive topicId, eggId and content only; success is confirmation, never invented points or reward details. No automatic collection retry.

## Source map

Flutter baseline: a63e9e91c82a3282e8dd7138f943b1a8cbfc021d
- lib/data/api/play_api.dart:198–238 companion/egg; 240–320 encounter and check forms
- lib/data/models/play_check.dart complete problem/receipt/reroll projection
- lib/data/models/checkin_models.dart:970–1005 egg model, usable constraints/default/clamp; PlayNodesResult eggs projection
- lib/feature/play/play_session_page.dart:426–535 probe/action/recovery; 705–782 egg tracking/display
- lib/feature/play/play_session_controller.dart:81–83 session companion, 588–590 3500ms display, 700–740 navigation milestones
- lib/feature/play/widgets/journey_check_stage.dart:57,136–168 server-only actions/results/exit

## Verification

Source assertions PASS (16 checks). Tree-sitter parse PASS for 9 new Swift files plus 5 patched shared-host copies (14 total), 0 recovery diagnostics. Host-hook application PASS on copied shared files only. These are supplementary source/syntax checks, not Swift typechecking, XCTest execution, Apple build, runtime, VoiceOver, backend or permission acceptance. Core tests and UI flows are authored. All Apple/runtime/live/network validation: NOT_RUN.
