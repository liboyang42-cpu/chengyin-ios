# Personal story gameplay draft selection (local authoring candidate)

Current repair: see [R2 confirmed existing-envelope save and inner JSON validation](project-story-template-r2-repair.md). The counts and 24-path evidence below describe the separately frozen first candidate; R2 adds targeted safety repairs without changing the six UI journeys.

## Scope and status

This increment connects the personal city-story editor to a typed existing-draft chooser. It provides immutable insertion review, cancellation/back navigation, explicit one-time local adoption, and account-scoped saved-draft restoration. It does not create or edit remote templates. Production source injection remains `nil`; the separate read adapter is default-denied by both endpoint approval and live capability checks. AppSession, AppCompositionRoot, the live permission registry, CI workflow and existing duration profile are unchanged.

This candidate is **HOLD for integration and Apple validation**. The local feature is implemented and has synthetic full-flow test sources; those Swift/XCTest/XCUITest sources have not been executed. New UI methods require the separate budget/history integration described below. No remote service, repository publication, CI run, or release activation was performed.

## Local behavior

- Before each existing block and at the explicit story end, the chooser captures the existing chapter and exact stable gap. Missing anchors never become append.
- Every opening reads the personal draft list again. Requests use POST `api/template/my-list` with `draft_status=0`, empty personal `scope`, `pageNum`, and `pageSize=20`. This is distinct from the published reference list using `is_quote=1`. Pagination is limited to 50 pages / 1,000 drafts, disclosed in the chooser.
- The list is display-only. Selection reads owner detail from POST `api/template/myinfo` with only the typed member-template ID and prepares an immutable local insertion preview. Explicit Apply rereads the same owner detail and requires an exact decoded-source snapshot match before saving the captured proposed draft.
- Ordinary gameplay creates a fresh story node containing the real member-template ID and source title, no coordinates, and a node block with `locationRequired=false`. No answers, private source body, or remote configuration are copied into the local node.
- An enabled album copies its title and image/caption references into a `dream` display block. It creates no node and retains no template ID in that block. References are shown as text; no remote images are fetched.
- Back, Cancel, read errors, rejected configuration, stale callbacks, and failed local-save confirmation do not mutate the editor. Failed local save retains the same proposed insertion for a guarded retry. Applying claims the action before awaiting a fresh read, so double taps cannot create two insertions.
- The existing `ProjectStoryMediaGap`, editor lease, monotonic draft mutation revision, editor incarnation, typed pending-story host and local envelope store are reused. This adds no new draft store or submission journal. Existing pending materials remain exact and are never consumed or promoted by selecting a story draft.

## Validation boundary

Owner identity, positive typed member ID, draftStatus zero and detail delFlag zero are mandatory. Missing owner, published/public-only rows, deleted records, duplicate list IDs or duplicate cross-page IDs fail closed. Rows can be selected again after a failed detail read; there is no public fallback.

Only personal city chapters with the supported schema/required values and exact node references are eligible. Global duplicate chapter/node/block IDs are rejected. The existing 200-block insertion limit remains strict. Opening chapters must be first and cannot recruit; all their nodes must remain location-free. Ending chapters can receive album display blocks but never gameplay nodes. Ordinary templates with validationMethod 4/5 (scan/GPS arrival) are rejected for location-free gameplay; known non-arrival methods must be explicit. Album projection runs before that check, matching the source's display-only behavior.

Album parsing checks raw numeric schemaVersion 1 and actual Boolean enabled before invoking the existing advanced validator. Unknown album/image keys, unknown schemas, ambiguous other active behavior, root authoring behavior, and malformed sibling enable flags are rejected rather than silently discarded. An album must have 1–6 images. The intersection of template and destination limits is enforced without truncation: title 20 UTF-16 units, image URL 500 units with the existing safe-media validation, and caption 40 units. Missing and null optional captions are permitted. A validation-only copy removes null captions for the existing advanced validator; the original selected image array remains unchanged in the local draft.

## Source evidence and conservative differences

The audited Mini behavior is `pages/publish/fabu/index.js` at the retained blob `152937a1c1887d6cbdedf35ca198d7b332c60473`: story-game entry and album materialization (1220–1239), ordinary member-template binding (6892–6905), and per-opening draft list refresh (7019–7034). The independent published reference list begins at 7037. Private source code is not included in this candidate.

Backend source checks used `ApiTemplateController.java` 287–335 and 612–676 for personal owner/draft boundaries, `ChapterFlowCompiler.java` 100–118, 197–229 and 253–293 for special chapter/node/dream constraints, `CmsTopicServiceImpl.java` 4662–4671 for owned-template checks and the 4/5 arrival restriction, and `AdvancedGameConfigValidator.java` 272–290, 1687–1702 and 2405–2427 for album parsing/media limits. Strict native typing and unknown/mixed-content refusal are conservative differences from the backend's coercive legacy parser. Missing optional source helper files prevented a claim of exact Mini helper implementation parity.

## Submission remains unavailable

The existing backend approved release compiler still rejects `LOCATION_FREE_UNSUPPORTED`; album display blocks are outside that compiler's text-only publication capability. This increment does not broaden any publishing route or approval. The chooser explicitly says this is local creation and cannot currently be submitted or published.

An additional existing native rule remains unchanged: `ProjectEditChapter.hasRealStory` derives text only before the first node, regardless of `locationRequired`. Inserting gameplay before the first prose block therefore preserves/saves/reopens the intended local content, but the existing full-project submission review can report missing story. The chooser's immutable insertion preview is not a formal submission preview. This known discrepancy requires independent future review; it was deliberately not “fixed” by weakening publication validation.

## Authored tests and local checks

New Swift tests: 33 Core methods (17 selection/domain plus 16 exact read-adapter methods), 20 real App-model methods, and 6 complete UI journey methods. The App tests include the actual synthetic multipart transport through the real reader and real local persistence, not only a protocol mock. Six UI journeys cover ordinary/album at first/middle/end, immutable preview, Back/Refresh/Cancel, explicit Apply, exact pending preservation, source rereads, zero submissions, cold coordinator reconstruction, restore and resave of the actual restored editor.

Twelve new Python structural checks validate wiring, boundary predicates, default denial, explicit adoption and all 16 bilingual keys. The full native contract run completed with 2,026 discovered checks: 1,980 passed, 46 explicitly skipped, zero failed. The pinned supplementary parser reported 18 changed/new Swift files with zero recovery diagnostics. Deterministic Xcode generation/scaffold passed (1,378 Swift sources, 7,853 bilingual keys). These checks do not compile Swift, run Apple SDKs, execute XCTest/XCUITest, or establish accessibility/runtime correctness. All previous Tests file bytes are retained unchanged.

The complete existing tooling suite ran 320 checks: 307 passed, with 5 failures and 8 errors in the historical/current club budget expectations caused by the six new method identities. No previous tests were removed or loosened; this is an explicit integration HOLD. Gitleaks found 42 pre-existing documentation/test findings with zero new relative-path/rule/line findings against the exact baseline. No allowlist was changed.

The unchanged live budget profile does not yet include the six new complete methods. `project-story-template-ui-budget.json` records source-bound **UNMEASURED engineering assumptions**, 900 seconds per full method including all helpers, 5,400 additional seconds, and exhaustive candidate forecasts. They are not observed times or hard runtime upper bounds. Candidate inventory is 718 UI methods / 153 classes. The existing 67-shard forecast is 1,907.064 seconds with the unchanged 300-second startup reserve, exceeding the 1,800-second deadline. 72 shards first fit narrowly; 73 preserve a 30-second margin. The parent must integrate budget/history projections and reevaluate all gates separately. No prior cost, test, deadline or safety floor was reduced.

NOT_RUN: Swift typechecking, SwiftPM tests, Apple SDK builds, AppUnit/XCUITest, simulator/device interactions, VoiceOver, Dynamic Type, actual Keychain runtime, live CN/US owner reads, network approval activation, backend deployment, and publication.
