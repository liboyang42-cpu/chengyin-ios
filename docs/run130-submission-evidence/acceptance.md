# Submission evidence presentation scopes and AX values

Base is the UNPUBLISHED dfa7f1ca26aaa0522e7fcaa7641d9c1980ea45c3 readiness candidate, descended from published 11800193 / tree30cd. Creator scene-host, UI3 version-label and UI21 fixture-inset candidates are not included.

## Proven failure and scoped source correction

Run130 jobs112840750118/356/353/443 expose the same acknowledgment twice: a receipt ScrollView and the editor Form CollectionView. Both are real deliberate EvidenceView instances. A global auditTaskID query is ambiguous. Current UIKit labels also combine the field description with its value (`Review task ID, 3301`), so scoping alone would still not satisfy the exact data assertion.

Each of the five read-only LabeledContent fields now declares one AX element with its original localized description as label and its exact existing display value as value. Topic/task IDs, original localized state/boolean values, and the original comma-space ID list are unchanged. The visible LabeledContent order and all acknowledgment business data stay the same. These are exact prior UI strings, not a change from localized Pending to server PENDING.

The modal ScrollView has a receipt identity; the retained editor EvidenceView has a separate history identity. Neither legitimate history nor the receipt is hidden to satisfy a test. No behavior, grant, storage, request or publication path changes.

## Exact test migration

Eighteen existing one-method UI classes have 60 positive source call sites:57 run in their full methods and3 are retained in an already-unused helper. Every call states its expected receipt/history phase. The new helper uses query.element for both the expected container and its field; XCTest is expected to reject zero or multiple matches. It never chooses firstMatch or a fallback container. This implicit-unique runtime behavior has NOT been validated on Apple for this candidate.

All original expected UTF8 bytes are compared with the String accessibility value. Other generic value/tap/launch/inspect helpers are unchanged, including every existing button count assertion. Original per-file reveal-before-wait or wait-before-reveal order,65/70 swipe maxima,5-second waits, language, maximum text and full journeys are preserved. Two original signout/no-ack absence assertions now require zero matching field identities across all AX roles, avoiding a vacuous StaticText-only negative after the semantic role changes.

The source contract pins all21 initial App/UI files, all168 actual UI Swift sources and the exact167-source previous directory. A restricted inverse restores every original file and every pre-existing assertion for historical source checks; the new actual sources are validated before projection. It is not installed into the central planner and cannot make changed actual tests inherit stale budget evidence. Negative controls reject wrong phases, duplicate field/container identities, firstMatch/fallback, substring comparison, altered expected bytes, weakened absence, longer waits and source omissions.

## Budget HOLD

Planning adds a conservative UNMEASURED2 seconds for each extra nested-container lookup or broadened global absence query:57 positive reads plus2 negatives =118 seconds. No old floor is reduced. Six methods remain756–778 seconds;12 rise to902–908 and exceed the existing900 planning cap. Current736 methods/162 classes are unchanged; one new helper adds a source file. Forecast total104625.381 seconds is not a schedulable approved plan. The prior79-shard profile/runner/workflow are byte unchanged and will reject this new source inventory. Adding shards cannot fix per-method over900.

All existing six930 proposals remain unapplied. This source candidate must remain integration/publication HOLD until a bounded diagnostic or an approved complete-journey plan resolves the current planning evidence. See validation-plan.md. Do not cite failed prefixes, source parsing or old run durations as this candidate's actual completion time.

## Verification limits

Swift tree-sitter parsing and Python source/structural checks do not compile Swift or exercise UIKit. Exact field values, implicit uniqueness, VoiceOver grouping, both scopes, signout retirement, cold fixture reconstruction and the18 complete journeys need Apple execution. Official semantic guidance: https://developer.apple.com/documentation/swiftui/view/accessibilityvalue(_:)-2bwuz and https://developer.apple.com/documentation/swiftui/view/accessibilityelement(children:).
