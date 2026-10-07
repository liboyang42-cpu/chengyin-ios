# City-orientation route map

Status: implemented candidate; Apple execution and live coordinate acceptance remain NOT_RUN.

## Scope and source behavior

This is an optional route overview in the personal city-orientation runtime (mode 1). It supplements the existing current-task and node-list entrances. It does not modify the permanent-city board, fog, shared location, Project authoring, or account settings.

The retained mini-app's on-demand story-map entrance and return-to-story behavior were inspected as behavioral reference. No private source, map artwork, provider configuration, location collection, external navigation command, or routing-service implementation was copied.

## Safety and behavior

- The sole node input is the existing authorized snapshot's `visibleNodes`. Branch visibility continues to be decided by `PlaySnapshot`; raw result nodes cannot become map markers.
- The presentation contains only ID, visible order, label/address, coordinate and state. Locked rows are generic placeholders with no name, address, coordinates, story, reason, or task action. Hidden rows have no presence.
- Only a confirmed current stop and unlocked completed stops can open the existing node destination. Current selection prefers an eligible authoritative current/recommended ID, then the existing single-current-task projection. Multiple unconfirmed alternatives do not fabricate a current stop.
- Every visible row remains in the list, including rows with no valid coordinate. A map-collapse control precedes the MapKit subtree so map gestures cannot prevent using the list. Text wraps; targets have a 44-point minimum; English and Simplified Chinese are supplied. States have symbols and text, not color alone.
- Finite latitude/longitude ranges are checked; zero and valid boundaries are retained. Missing, partial or invalid coordinates do not create a pin. Restricted/missing-coordinate gaps are not joined by a line.
- Dashed segments show supplied stop order, never road geometry, walkability, directions or distance. No location provider, `UserAnnotation`, geocoder, directions request, new network grant, or progression action is introduced. The existing MapKit basemap may load its normal map tiles.
- Node selection binds the exact snapshot and `PlayInteractionContext`, plus retained coordinator identity. Byte-identical reloads still invalidate old selections. Scope, account/epoch, route version/session, mode and coordinator changes fail closed.
- An already-open task remains mounted during that task's existing review/submission phase. This is presentation continuity only: no new selection or command authority is issued while busy. Refresh/failure/new read invalidates it. Back/reopen does not persist selection.
- No central Composition, Session, capability registry, CI gate, UI sharding, duration budget, or existing UI test method is changed. Project references are deterministic output from the existing generator.

## Authored acceptance

- 12 Core tests: mode/availability, hidden and branch filtering, locked redaction, current disambiguation, completed replay, unknown state, coordinate boundaries/strings/gaps, and preserved input order.
- 8 app-unit tests: current/completed versus locked/hidden admission, identical refresh, account/epoch/guest return, scope/coordinator replacement, route session/version membership changes, failure/mode invalidation, and review/cancel presentation continuity.
- 8 UI tests: current/completed/original entrance, all-missing coordinates, spoiler suppression, refresh while pushed, account/back/reopen/relaunch, Chinese maximum-text dark environment, free-mode exclusion, and existing task review/cancel. These use the production view and scripted synthetic transport; their existence does not prove execution.
- 7 focused Python source contracts. Whole-source contract and project structural evidence are stored in the candidate package logs.

## Explicit remaining acceptance

Swift typechecking and XCTest, app-unit hosting, CN/US/device builds, XCUITest, screenshots, VoiceOver, MapKit rendering/interaction, actual basemap availability, physical device, real accounts/server data and coordinate-system/map placement correctness have not run in this Linux workspace. No signed build, release, push, or live provider request was performed. Real walking safety is outside this illustrative map's claim.

`tools/check_play_runtime_hosts.py` has an existing baseline failure at its `public func reviewedPhoto()` source assertion; the baseline and candidate produce the same result. The compile-only recovery boundary checker reports NOT_RUN without Apple Swift. No unrelated code was changed to silence either result.

## UI duration assumptions for integration

`ui-budget-assumptions.json` records conservative estimates only. They are not measured XCTest durations. The central reviewer must merge them with the other feature lines, regenerate the central inventory/shards, and run the normal completeness/budget gate. This lane deliberately does not modify the shared budget or CI files.

## Local result ledger

- PASS: deterministic project/scaffold checks (1,369 Swift app/test references; 7,862 bilingual keys).
- PASS: 7 focused source contracts; complete source-contract suite ran 2,017 tests, with 46 existing missing-source skips.
- PASS: strict pinned Tree-sitter parse of the 8 touched/new Swift files (advisory parser only); original map alternative-list contracts; whitespace checks.
- PASS: all 150 pre-existing UI test source files are byte-identical to the baseline.
- NEEDS CENTRAL INTEGRATION: tooling suite ran 294 tests, with 3 failures in `test_creator_pending_budget.py`. Adding this suite changes the inventory from 710 methods / 146 classes to 718 / 147; the unchanged central default adds 480 seconds. Those historical inventory/cost snapshot assertions require central integration across all feature lines. This is not an Apple test failure and has not been hidden.
- BASELINE FAILURE: the legacy runtime-host checker fails identically on baseline and candidate; both logs are supplied.
- NOT_RUN: Apple Swift compilation/tests, Xcode builds, UI execution, the compile-only protected-recovery boundary check and all live/device acceptance.
