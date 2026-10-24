# CY-HANDOFF: IOS — I05 revoked edit-history readback

2026-10-15 UTC. **SOURCE_CANDIDATE / EXECUTION_NOT_RUN / NOT_PUSHED**. This is one bounded existing-workspace fix, not acceptance of the full I05 privacy card.

## Identity, scope, and backend dependency

- Native branch: `liboyang42-cpu/chengyin-ios:migration/native-ios`.
- Published parent: `e2ef0373f4bb9ae233848c8aca75581e8ebaa94b`, tree `9a6611e14980da86ab7d45712b34cb11e2a4dcc1`. The candidate is isolated from that exact published snapshot; no old unsubmitted cumulative implementation was imported.
- Native scope: the existing community author workspace's edit-history read, display, rejection, retry, and lifecycle invalidation. Existing legacy/community lanes, author states, private drafts, mutation journals, and grant defaults are preserved.
- Read before adaptation: `ios-current-status.md`, the native README, and backend `IOS_START_PROMPT.md`, `IOS_HANDOFF.md`, `BACKEND_CHANGES.md`, `COORDINATION.md`, `OWNERSHIP.md`, and `TASKS.md` at control `da842579ec1e8ad886a9c4dfc767509ae81134b1`.
- Dependency: **B05 / BK-PRIVACY, CONTRACT_FROZEN, NO_API_CHANGE**. The user-approved deleted-author read restriction is in `e437a52747c8c9d7468abf743942aca36e871da2`, included in frozen candidate `1e403b135206844a34219753a36e2dee39c7dd59`. Current control records source evidence; **TEST_DEPLOYED=NO**, runtime target/package/account binding remains unverified. No CI was queried in this iOS task.
- Exact source read: `ApiCommunityPostController.java`, `CommunityPostServiceImpl.java`, and `CommunityPostMapper.xml` at `1e403b13`. Their Git blobs are unchanged at later candidate `4a943501262cb533158428d9748d8ac49aaa8950` (`4c74911e`, `23970f7b`, `c959fa07`, respectively).
- Native `AGENTS.md` and local `.agents/skills/*/SKILL.md` were not present in the supplied snapshot or applicable ancestors. The engineering skill and README instructions were consumed. Current user instructions defer every test/build/app/CI execution.

## Confirmed existing source gap

The existing route is Square -> an author workspace -> server drafts -> Edit history. `SquareWorkspaceCoordinator.revisions` already reads GET `/api/v1/community/posts/{id}`, verifies the author, then reads GET `/api/v1/community/posts/{id}/revisions`. Both service-side reads use current parent visibility; revisions also requires the author.

Before this change, `SquareWorkspaceView.revisionsText` changed only on success. A later detail or history rejection raised the generic error alert but left the previous raw edit-history body visible. Concurrent history reads also had no view-level post/request generation: a late successful earlier response could replace a later selection. Leaving or backgrounding the workspace did not invalidate that history string.

Sanitized source reproduction, not an executed device test:

1. Synthetic author 81 reads post 701 and displays history containing `Old private body`.
2. The authoritative fixture subsequently rejects the same post, representing an externally completed deletion or lost visibility. Real deletion is not performed by this task.
3. Tap Edit history again. Detail returns HTTP 200 with AjaxResult business `code:404`, or detail succeeds and the revisions endpoint returns business 404.
4. Before: the alert appears while old history remains. Expected: clear the old projection before revalidation; show no history on rejection, malformed response, cancellation, or timeout. A later successful explicit read may display a new authorized response.

The server controller wraps its business error in AjaxResult. This patch does not mistake business 404 for an HTTP status and does not infer that a timeout proves deletion. There is no new endpoint, visibility policy, synthetic deletion success, or media revocation promise.

## Change and natural recovery flow

- `Core/SquareWorkspaceCoordinator.swift`: own transient `revisionPostID`, `revisionData`, and loading state. Every history attempt clears the previous body before connecting. The row captures an opaque, single-use read intent synchronously before enqueuing its task. Invalidation rotates that intent; queued old work rejects before any GET, and cannot clear a newer result. The intent and existing account/namespace/epoch checks bind both stages. Superseded success and failure become cancellation and cannot update a newer selection. Clear on owner hydration/resume, first-page server refresh, existing explicit location-withdrawal entry, and detected session change.
- `App/SquareWorkspaceView.swift`: render the coordinator projection with its post ID and existing loading/error controls. Reuse the existing row action for explicit retry. Clear history on disappearance, background/inactive state, changed draft, lane, or session. Do not retain a second success-only local copy. The history-only action ignores cancellation instead of showing a stale alert over newer work; the generic action helper is unchanged.
- `Tests/CoreTests/SquareWorkspacePrivacyReadbackTests.swift`: 17 synthetic regression methods authored. Swift Package already discovers this directory; no Xcode project or production composition change is needed.
- `docs/ios-current-status.md`: link this I05 slice without promoting the whole card.

The retry still performs the existing detail -> author check -> history chain, and only a fresh successful response supplies displayed history. First-page workspace refresh invalidates history even if that refresh fails. No draft or pending-write storage is deleted. No existing write lock or request identity is reset. The ordinary `AppSession.squareWorkspace()` continues to inject no service, with live/media/legal grants OFF.

## Authored acceptance vectors and evidence level

The 17 unexecuted methods cover exact read requests/cache policy, post-bound successful display, business 404 at detail and at revisions, timeout followed by fresh retry, clearing before a suspended new-post read, out-of-order successes and failures, dismissal/background invalidation, queued-intent invalidation before task start without disturbing newer results, pre-start cancellation, single-use intent enforcement, invalidation during detail stopping the history request, account/epoch replacement, non-owner denial, legitimate non-deleted author lifecycle compatibility, server-refresh failure preserving unsent drafts, and default-OFF no-request behavior. Multiple vectors are intentionally grouped within methods; counts are source method counts, not passes.

Only source reading, diff/byte inspection, and patch/file identity generation were performed. **Swift/Core XCTest, AppUnit, XCUITest, Xcode builds, simulators/devices, accessibility, Python/Node/Java test suites, lint, CI lookup/dispatch, real HTTP/accounts, database actions, and real deletion/revocation: NOT_RUN.** No merge, deployment, credentials, production DDL, backend/shared-log edits, payment, or capability enablement occurred.

This slice does not claim immediate server-push revocation while the workspace is continuously open, or cache eviction/revocation at OSS/CDN/other media consumers. Two real identities, deleted links, withdrawn references, media URLs and device behavior still need approved-environment verification. A local projection invalidation is not a substitute for server authorization.

## Sources and rollback

- [Current backend control](https://github.com/liboyang42-cpu/hengyin/blob/da842579ec1e8ad886a9c4dfc767509ae81134b1/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md)
- [B05 exact contract](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/docs/verification/mini-bug-arch-20261015/B05/CLAUDE-CONTRACT.md)
- [Author deletion visibility policy](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/chengyinhub-system/src/main/resources/mapper/business/CommunityPostMapper.xml)
- [Detail/history source](https://github.com/liboyang42-cpu/hengyin/blob/1e403b135206844a34219753a36e2dee39c7dd59/chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/CommunityPostServiceImpl.java)
- [Native published parent](https://github.com/liboyang42-cpu/chengyin-ios/tree/e2ef0373f4bb9ae233848c8aca75581e8ebaa94b)

Rollback is limited to this candidate's two implementation files, dedicated regression file, and iOS documentation delta. No schema, persisted envelope, backend API, grant, or journal migration exists. The coordinator's existing `revisions(postID:) -> Data` interface is retained.
