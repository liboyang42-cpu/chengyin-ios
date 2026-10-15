# CY-HANDOFF: IOS — I11 retained poll return/readback

Protocol: `CY-COORD-20261015-v1`. Date: 2026-10-15 UTC.

## Scope and exact baseline

- Repository/branch: `liboyang42-cpu/chengyin-ios`, `migration/native-ios`.
- Published parent: `fed79fede32be99e81fcd5c9b0e6a8c3e0bbb141`; tree `51f6cabf5eb7d9069b6b6249380dde64a16d8c21`.
- Status at authoring: source candidate, pending independent review/publication. This document does not claim a later commit or an executed test pass.
- I11 classification for this slice: **existing native entry with a source-confirmed lifecycle gap**. Group polls were already implemented, mounted and retained. This is not a new poll product, a new backend, or a reversal of the mini-program scope decision.
- Related BK: **BK-EXISTING, NO_API_CHANGE**. Existing poll-specific contracts remain authoritative; no game-session receipt endpoint, new `requestId`, or new authorization semantics are imported.
- Unique write scope: `Core/GroupPollCoordinator.swift`, `Tests/CoreTests/GroupPollTests.swift`, this document and `docs/ios-current-status.md`. No shared backend/control logs, project registration, runtime grants or localization files are changed.
- The public parent tree contains no `AGENTS.md` or repository `SKILL.md`; the repository README's build/test instructions were read. The current source-only instruction defers all execution.

## Ordinary source path and sanitized reproduction

Existing entry points are unchanged:

1. [MessagingHistoryView](../App/MessagingHistoryView.swift) opens the existing create sheet; [MessagingMessageDetailView](../App/MessagingMessageDetailView.swift) opens a type-4 poll card's result page.
2. [AppSession](../App/AppSession.swift), `groupPollCoordinator`, retains the coordinator by account/epoch/conversation/reference. Returning can reuse the same coordinator while an earlier request is outstanding.
3. [GroupPollView](../App/GroupPollViews.swift) calls `resume` on appearance, `refresh` on detail entry, and `suspend` on disappearance. It presents the coordinator's existing review/unknown/acknowledged states, and explicitly invokes confirmation or exact creation retry.
4. [GroupPollCoordinator](../Core/GroupPollCoordinator.swift) uses the existing result read, membership read and metadata-only pending journal. [GroupPollService](../Core/GroupPollService.swift) and its scoped session client supply the unchanged HTTP boundary.

Source-confirmed interleavings, not executed device reproductions:

- Synthetic account 7, conversation 12, poll 31: load results, review option 51 and confirm. The journal is reserved and the vote request is dispatched. Leave before its result; `suspend` keeps UNKNOWN. Reopen and independently read the server's recorded vote, resolving the vote lock. The creator can now review or submit closure. On the parent source, the old vote's success **or failure** unconditionally sets phase to UNKNOWN, replacing this newer review/submission even though the original lock was resolved.
- A close request can similarly return after a newer CLOSED readback and revive UNKNOWN with no remaining journal lock.
- A create request can return after a matching message resolves its stable key and the retained composer resumes a new draft, or after the original immutable create has been explicitly retried successfully. The old callback can replace the new state.
- A preflight result read can fail after departure and a new vote review; its old failure sets phase to idle and cancels the newer review, despite no original dispatch.
- A result refresh assigns the awaited membership result **before** checking its generation. An old member/non-member result can replace the newer membership presentation, hiding valid actions or displaying stale ones. Every actual write already rechecks membership; this is not a demonstrated backend authorization bypass.

Expected: only the current request lifetime may publish its presentation. Departure preserves genuinely unresolved intents; a newer authoritative readback, review or submission cannot be overwritten by the retired request. Public shipping capabilities remain OFF, so none of these traces is claimed as a live-user incident.

## Source change and preserved behavior

- Membership is first captured in a local value, then published only after the existing account/generation/cancellation fence succeeds.
- Every asynchronous dispatch/preflight completion that is no longer current uses one interruption helper. A retired generation makes no presentation update. The departure/new read already owns recovery state.
- Cancellation within the same generation ends submission without declaring an unobserved write failed. A reserved intent remains UNKNOWN. If an exact-create retry is canceled before reloading its existing record, its original pending intent still keeps the UNKNOWN/retry path.
- The synchronous post-journal guard remains: a journal callback that invalidates scope must retain the just-written lock and prevent dispatch. This guard is before the network await, unlike the stale network completions repaired here.
- No retired completion clears a journal record, restores old poll content, overwrites a new reference, or automatically retries. OPEN/no-choice readback still cannot clear an uncertain vote; CLOSED or the server's recorded choice remains the existing readback proof. A matching create key can still reconcile through its actual message.
- Creation retains exactly its original immutable payload/key for an explicit retry. Vote and close still offer readback rather than an invented replay contract. Creator-only closure, version CAS, historical read access, current-membership writes, account/realm isolation and OFF grants are unchanged.

## Refreshed backend evidence

Read before adaptation:

- Control branch `codex/mini-bugs-backend-cloud-plan-20261015` at `8533507d637199e3143356509de3e384a74c57be`: [IOS_START_PROMPT](https://github.com/liboyang42-cpu/hengyin/blob/8533507d637199e3143356509de3e384a74c57be/docs/plans/mini-codex-cloud-20261015/IOS_START_PROMPT.md), [IOS_HANDOFF](https://github.com/liboyang42-cpu/hengyin/blob/8533507d637199e3143356509de3e384a74c57be/docs/plans/mini-codex-cloud-20261015/IOS_HANDOFF.md), [BACKEND_CHANGES](https://github.com/liboyang42-cpu/hengyin/blob/8533507d637199e3143356509de3e384a74c57be/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md), COORDINATION, OWNERSHIP, TASKS and LONGRUN_CURRENT.
- Frozen historical candidate: `1e403b135206844a34219753a36e2dee39c7dd59`. Its old validation does not transfer to this native change or the rolling backend.
- Actual CORE [PR44](https://github.com/liboyang42-cpu/hengyin/pull/44) head read: `2b1984b59a0929a360e8095d5fc1955a1aed7964`, open draft, unmerged. Actual independent EXTRA [PR36](https://github.com/liboyang42-cpu/hengyin/pull/36) head read: `25ede65815d26d1514d3b6c3b92b26d2898a3e45`, open draft, unmerged. They are separate candidates, not one deployed package.
- Directly reread CORE's [ApiImPollController](https://github.com/liboyang42-cpu/hengyin/blob/2b1984b59a0929a360e8095d5fc1955a1aed7964/chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiImPollController.java) (blob `f8aa4d0754e5d64e78eed91653c8789ba268e97b`), [ImPollServiceImpl](https://github.com/liboyang42-cpu/hengyin/blob/2b1984b59a0929a360e8095d5fc1955a1aed7964/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/ImPollServiceImpl.java) (blob `6ca728e46cebae160ab98448cb35e0e7008cc445`) and [ImPollMapper](https://github.com/liboyang42-cpu/hengyin/blob/2b1984b59a0929a360e8095d5fc1955a1aed7964/chengyinhub-system/src/main/resources/mapper/business/ImPollMapper.xml) (blob `b11d9d348bc0dc781c01b4e4ade9965ae08ec842`).

Exact retained contract: POST `/api/im/poll/result` with form `poll_id`; POST JSON create/vote/close; stable `clientPollKey` and matching fingerprint only for create; close uses `expectedVersion`; current group membership is checked for writes; historical audience may read; one vote cannot be changed; errors remain AjaxResult business codes. Create responses do not establish result totals. No field or policy adaptation was necessary for this lifecycle fix.

The control record keeps **TEST_DEPLOYED=NO** and rolling source **SOURCE_DELIVERED_UNVERIFIED / NOT_RUN**. No running application package, database binding, authorized account or HTTP business readback was verified. No CI run/status/log was queried or triggered by this slice.

## I10 bounded no-change review

Before choosing this I11 existing-flow defect, the named I10 sources were inspected on the exact native parent:

- [WalkingNavigationView](../App/WalkingNavigationView.swift) uses a view task, cancellation-aware polling, departure pause and camera invalidation; [WalkingNavigationCoordinator](../Core/WalkingNavigationCoordinator.swift) invalidates generations and stops location/planner work. It also has existing large-text summary/step-sheet handling and controls with explicit labels.
- [PlayRouteMapView](../App/PlayRouteMapView.swift) uses business stop IDs, a list alternative, lifetime-scoped camera requests and selection retirement. [PlayExperienceView](../App/PlayExperienceView.swift) retains its existing presentation-key integration; no replacement map/player UI was needed for this slice.
- [QuestifyMotionComponents](../App/QuestifyMotionComponents.swift) already consults Reduce Motion for relevant content animations. [AccessibilityPresentationFlowTests](../Tests/AppUITests/AccessibilityPresentationFlowTests.swift) explicitly identifies its environment overrides as synthetic, not a VoiceOver audit.

**NO_CHANGE_SOURCE_REVIEW only for these inspected paths.** This is not a complete I10 audit, performance improvement, memory/resource-leak proof, or accessibility acceptance. No same-scenario device measurements exist for this slice. The actual map/long-list/image/audio performance, VoiceOver focus/hit targets, maximum Dynamic Type and representative OS/device acceptance remain unverified. No speculative map rewrite or cosmetic-only patch was introduced to manufacture completion.

I11's other candidate entries (official routes, received stamps, reports, state-key tools, claims) are not declared fully reviewed, absent, approved or complete by this poll-specific slice. Existing [group-poll](group-polls.md), [roaming](roam-experience-module.md) and [creator](creator-content-integration.md) work remains preserved. CLAIM-MATERIAL and other unapproved contracts are not guessed.

## Authored regression scope and evidence levels

Thirteen new Core test methods are added to the already registered `Tests/CoreTests/GroupPollTests.swift`. The test doubles deliberately delay replies using explicit continuations and ignore cancellation until released. They cover:

1. Late vote success after readback and a new close review, followed by explicit confirmation.
2. Late vote failure while a successor close is submitting, preserving its separate lock.
3. Late close success and failure after a CLOSED readback.
4. OPEN/no-choice readback retaining UNKNOWN despite a retired vote receipt, then real choice readback resolving it.
5. Retired create success after matching-message reconciliation and a new draft review.
6. Retired create failure after a successful exact-key retry.
7. Old preflight failure after a new vote review, then successful explicit confirmation.
8. Old membership success after a newer non-member read.
9. Old membership failure after a newer member read, then a current explicit vote.
10. Same-lifetime preflight cancellation without dispatch.
11. Exact-create retry cancellation preserving the original UNKNOWN intent and payload.
12. Same-lifetime post-dispatch cancellation preserving its original lock.
13. Account-epoch replacement before a late close completion.

Existing normal contract, review/cancel, journal failure, synchronous journal invalidation, immutable replay and unknown-outcome tests remain intact. No new fixture route, production transport, project file or runtime feature grant is introduced.

| Evidence layer | This slice |
|---|---|
| Source inspection, ordinary entry/lifecycle trace | Performed; no runtime reproduction claim |
| Public parent file/tree and candidate patch identity | Packaging evidence only; not a test or compile result |
| Core XCTest | 13 new methods authored; all execution NOT_RUN |
| AppUnit / XCUITest / static contract / lint / typecheck | NOT_RUN; existing suites not rerun |
| Xcode build / simulator / App launch | NOT_RUN |
| Device / VoiceOver / performance / real account/backend/provider | NOT_RUN / NOT_VERIFIED |
| CI | Not queried, dispatched, rerun or awaited |
| Merge / backend deployment / signing / application release | Not performed; capabilities remain OFF |

No whole-card or full-product acceptance is claimed. Any later validation needs the exact published native candidate, current backend contract/deployment evidence and separately authorized Apple/runtime execution. Revert only this native slice if needed; never delete unresolved intent records to make recovery appear successful.
