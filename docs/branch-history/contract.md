# Current-run branch history

Status: implementation and authored tests, awaiting Apple execution. This slice is read-only.

## Contract evidence and limits

The existing mini-program `_buildBranchPath` consumes route-state `decisionLog`; the backend `TopicRouteState` exposes the list, `TopicRouteEngine.appendLog` appends a record in order, and `TopicRouteRuntimeServiceImpl.toView` copies that list from the current route session. The native schema consumes only `fromNodeId`, `toNodeId`, `edgeId`, and `at`. No private implementation source is included in this slice.

This is the current route session's server ledger, not a lifetime account history. The existing `/api/play/nodes` followed by authoritative `/api/play/route-state` reads and existing `PlaySnapshot` same-session/nondecreasing-version check remain unchanged. The history always uses `snapshot.route` (authority), never merges an earlier nodes-response history into a newer authority response, and makes no additional request.

## Optional and bounded decoding

- The `PlayRouteState.decisionLog` property is optional and additive. Missing, null, wrong-type or oversized history produces no history facts, while the original route still decodes under its existing rules. Invalid route authority still fails exactly as before.
- Maximum retained input is 200 records. Oversized lists are rejected whole, not silently truncated into an apparent full history. Unknown recursive fields are not decoded into generic wire values.
- Each row requires positive integer `fromNodeId` and `toNodeId`; decimal-string IDs are accepted up to 19 bytes with digits only and `Int` range validation. Bool, nonintegral, negative, zero, missing, overflow or nondecimal IDs discard the row.
- Bad rows are counted and excluded with a visible incomplete-list notice. Remaining rows retain original server positions, so skipped rows cannot relabel later steps. An all-invalid list is unavailable, not a successful empty read. A valid empty list is explicitly empty.
- `edgeId` is optional plain text, at most 128 UTF-8 bytes and no controls. It is neither identity nor a destination. Repeated edges and loops are not deduplicated. SwiftUI row identity is the record's original array position within this selected read.
- Timestamp input is optional. Positive numeric Java Date values are milliseconds and are shown with explicit UTC. No seconds/milliseconds heuristic is used. Zero, negative, overflow, malformed and missing times show a neutral time-unavailable label. Values are bounded through year 9999. Valid server wall-clock strings stay verbatim with no device-timezone conversion; ISO-8601 values must have a timezone. Calendar-invalid dates are rejected. No clock-relative “ago,” time sorting, duration or completion inference occurs.
- Bounded decoded values are not a claim to limit Foundation JSON parser allocation before decoding; the existing transport payload limits remain outside this feature's scope.

## Presentation and privacy

The only production entry is the existing `PlayTaskSummaryView`, for city-orientation branch snapshots in `ready` or `unknown` phase. A sheet shows the run's server sequence and returns to the same summary. Empty and unavailable branch data still have an explanatory destination. Linear and free-exploration modes have no entrance.

Names come only from `snapshot.visibleNodes` under current authority. Hidden, absent, missing, blank, control-containing or over-512-byte names use a neutral localized label. No raw node ID, edge ID, hidden name, node jump, URL or alternate destination is shown. Names are plain text. The history view receives no service, capability, callback for gameplay, answers, rewards or route advancement.

The selection stores only scope, route session ID and exact route version. It projects no rows if the current snapshot is nil or no longer matches. The summary clears presentation on changed selection, non-display phase and disappearance; the existing coordinator clears its snapshot before a refresh awaits and checks account/epoch on every snapshot read. The feature stores no cross-read rows. Its account lifetime depends on the existing normal summary being owned and removed by that coordinator; it does not invent a second account or session authority. Apple UI tests explicitly exercise refresh and account replacement while the sheet is open.

All feature strings are in the dedicated `PlayBranchHistory.xcstrings` table (English and Simplified Chinese). Every text block can wrap, with no fixed height, truncation or custom animation. Row and normal summary layout tests cover accessibility5 at narrow width; UI journeys include Chinese maximum text/dark mode and reduced-motion fixture policy. VoiceOver and layout success are not claimed until Apple execution.

## Authored coverage

- 16 Core XCTest methods: old payload compatibility, 200/201 boundary, empty/unavailable, invalid IDs, positive/string IDs, repeated edge order, gap indices, hidden/unknown names, missing/invalid times, numeric milliseconds/ISO strings, bounded edge data, nonbranch/free modes, exact selection lifetime, authoritative replacement and unchanged progress.
- 5 AppUnit methods: normal summary/history reopens with no extra request, GET-only reads, suspended refresh clearing, account/epoch failure clearing, old route session/version rejection, bilingual maximum-type wrapping and neutral naming.
- 5 UI methods: summary → history → return → reopen; Chinese large text → return → refresh → empty; missing/malformed/empty states; delayed refresh and account switch while presented; linear-mode nonentrance across refresh. These run the normal `PlayExperienceView` with the existing final offline recorder and only `.reads` enabled.
- 12 Python static contract checks are supplementary. They neither execute Swift nor establish UI behavior.

The independent unmeasured UI proposal is in `ui-budget-assumptions.json`. It does not change the central workflow, shards or duration weights. The integrator must recompute the combined budget after merging the other feature lines.

## Verification commands

- `python3 -m unittest discover -s Tests/ContractChecks -p test_play_branch_history.py -v`
- `python3 -m unittest discover -s Tests/ContractChecks -p test_reference_chat_task.py -v`
- `python3 tools/generate_project.py` and regeneration cleanliness check
- `swift test --filter PlayBranchHistoryTests` (not run here: Swift unavailable)
- `xcodebuild test -project Questify.xcodeproj -scheme QuestifyAppUnitTests -destination 'platform=iOS Simulator,name=<available device>' -only-testing:QuestifyAppUnitTests/PlayBranchHistoryAppTests` (not run here)
- Apple UI integration must include every `PlayBranchHistoryFlowTests` method exactly once under the merged UI budget (not run here).

No remote push or publication is part of this feature slice. Apple compiler/typechecker, simulator, device, screenshots and runtime evidence are all NOT_RUN in this Linux environment.
