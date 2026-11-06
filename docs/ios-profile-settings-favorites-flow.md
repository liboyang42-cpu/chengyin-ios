# CY-HANDOFF: IOS — Profile and Settings saved-post removal flow

## Source-only candidate

Baseline: `migration/native-ios@30adba500ab3d1746105e1de061bd9dab83a57d9`, tree `dd6e3b6b403fe08abad488c0a263efdfd5534def`.

This continuation integrates the existing native collection and saved-post removal adapter into ordinary Account and Settings navigation, then closes the result, error and return paths. It is one bounded source group, not a claim that all profile/settings work or the full product scope is complete. Existing post/topic readers, detail navigation, list states, pagination and the explicit removal contract are reused.

Status: **SOURCE-ONLY / NOT ENABLED**. All tests, builds, App/device execution and CI are **NOT_RUN** for this candidate, by instruction. Authored tests are source artifacts, not execution evidence. No production or integrated acceptance-fixture grant is installed. The composition selector remains the literal empty closure. Saved TOPIC removal is NOT IMPLEMENTED; topics remain read-only through their existing routes.

## Complete bounded interaction

1. **Entry:** Account keeps its existing favorites link. Settings gains a native favorites entry within its real sheet and NavigationStack. A route captures account/role/epoch, viewer revision, reader identity/scope/configuration, and optional removal-controller identity. A fresh push gets fresh local tab state. Back consumes the route; closing Settings permanently retires that owner. Older close/detail callbacks cannot affect a successor.
2. **List:** existing Posts/Topics lists preserve loading, empty, unavailable, error/retry and pagination states. No approval means unavailable reads and no removal action. Only legacy saved-post rows with an exact current approval can begin a removal. Current accepted rows still gate detail navigation; a saved topic is never sent to the post mutation endpoint.
3. **Review/cancel:** a fresh exact-target read prepares the review. Cancel, background/parent departure or changed account/scope retires only that presentation. Preparation retry is read-only. Confirmation consumes the review before awaiting, reads the target again and records the pending operation before the single explicit `bookmark=0` command. The existing review UUID remains the request ID.
4. **Known result:** success requires exact authenticated target state `isBookmarked == 0`, not a missing list row or a write acknowledgement alone. One presentation completion token is shared by the entry and sheet. Done, Close, swipe and lifecycle dismissal can deliver at most one refresh, and only to the captured still-current collection. A queued refresh cannot update a replacement scope.
5. **Unknown recovery:** a post whose removal applied may disappear from the saved list before its acknowledgement/readback arrives. A collection-level recovery section projects only exact currently approved targets with existing durable pending records. It needs no saved row or post body, opens directly in UNKNOWN and can only reread status. It never creates a write review, resends a command or invents a receipt endpoint. The rendered section remains present while its result sheet is open, even after the pending row clears.
6. **Return and authentication:** leaving/reopening Settings or Account reuses the current scoped controller and persistent journal. A matching HTTP/envelope 401 expires only that captured current session. Late responses, replacement/revoked capabilities or changed credentials cannot expire a successor or claim success. A post-dispatch 401 retains its pending record.

## Local cleanup and stale completions

A retired write or reconciliation used to restore its captured pending record after a newer presentation had already resolved and cleared it. Restoration has been removed from asynchronous failure paths.

After exact remote `isBookmarked == 0` has been established, cleanup executes synchronously. If local clear throws but a successful exact local reread returns nil, the removal and cleanup are known complete. This does not use an absent journal record as remote evidence. If a record remains or local reread fails, the controller stays fail-closed. A session-owned in-memory quarantine also keeps that exact target visible to subsequent controllers after retirement, capability replacement or reauthentication until local cleanup is verifiable. It does not replace durable storage and is not claimed to survive process death. Actual post-dispatch uncertainty still uses the existing durable journal; no durable write is cleared before an exact successful target readback.

Unreadable local state exposes a retryable local-state error and cannot authorize a new command. No cleanup path overwrites a different operation record. The shared quarantine is keyed by deployment/namespace/account and exact target; it supplies no grant.

## Composition and permission boundary

- `ProfileFavoriteRemovalAccess` binds an explicitly supplied approval to exact runtime context, collection scope, target, expiry and monotonic revocation. It creates no approval.
- The dedicated transport accepts only the two existing paths and exact bodies: target-only info read or explicit zero plus the existing request UUID. It rejects toggle/add/topic routes and extra fields. It rechecks the same access object, token, scope and context before and after dispatch.
- `AppCompositionRoot.profileFavoriteRemovalAccesses` defaults to `{ _, _ in [] }`. No App assignment supplies grants. Authentication, a list/detail reader, an unrelated social approval, a URL or a remote Boolean cannot enable the mutation.
- `AppSession` caches a controller only while context, scope and supplied access revisions match; missing/revoked/replaced accesses retire it. Existing scoped storage and current credential providers are reused.
- The pre-existing DEBUG removal fixture and test-only synthetic harnesses are reused. Their capabilities are not promoted into the integrated fixture or production.

## Backend coordination

Before adaptation, the public [iOS start prompt](https://github.com/liboyang42-cpu/hengyin/blob/e2163ab8fdd93c9548c74949604c9668c97f03ad/docs/plans/mini-codex-cloud-20261015/IOS_START_PROMPT.md), [iOS handoff](https://github.com/liboyang42-cpu/hengyin/blob/e2163ab8fdd93c9548c74949604c9668c97f03ad/docs/plans/mini-codex-cloud-20261015/IOS_HANDOFF.md), [BACKEND_CHANGES](https://github.com/liboyang42-cpu/hengyin/blob/e2163ab8fdd93c9548c74949604c9668c97f03ad/docs/plans/mini-codex-cloud-20261015/BACKEND_CHANGES.md), coordination, ownership and task documents were reread at control `e2163ab8fdd93c9548c74949604c9668c97f03ad`.

This is **NO_API_CHANGE** native composition/recovery work using the [existing saved-post adapter](../Core/ProfileFavoriteRemoval.swift) and its already documented explicit removal/readback contract. It does not infer a topic-unlike contract or a new backend permission from BK-EXISTING. No backend/shared-log edits, backend execution, external messages or deployment were performed. The public control still records TEST_DEPLOYED=NO. Its separately reported backend compilation is not native or feature acceptance. Actual target deployment, permission review and current-account integration remain required before any production grant.

## Authored evidence and remaining acceptance

- Existing Core tests extended for held retired writes/reconciles after newer recovery; missing-row recovery; wrong targets/scopes/expired identities; unreadable journal; cleanup verification/quarantine across controller replacement; current/stale 401; and retirement during prewrite read.
- App-unit tests cover stable composition, default-empty hiding, revoke/logout, Settings return with the applied target absent from a fresh list, matching-session expiry, idempotent dismissal and queued refresh scope changes.
- Existing Settings owner tests cover post/topic selection, repeated pushes, Back, old callbacks, revocation, account changes and background/retirement.
- Actual normal Account → Settings → Favorites unavailable-state UI acceptance is authored using the unchanged integrated fixture. It repeats Back/Done/reopen and verifies the absence of successful unauthorized fixture requests.
- The existing isolated DEBUG removal fixture now exposes a synthetic list refresh without changing its grants. Authored UI cases cover Done, Close, swipe and missing-row read-only recovery with the result sheet retained after journal clearance. These are not claims of enabled normal-route UI execution.
- New source/test/resource membership is registered in the existing Xcode project. The global localization catalog and all explicitly held feature files are unchanged; new copy lives in the dedicated Settings favorites catalog.

All of the above remains NOT_RUN. Only source inspection and patch/file/tree identity work were performed. Apple compilation, XCTest/AppUnit/XCUITest, actual Account/Settings enabled UI behavior, accessibility, foreground/background timing, process restart with real storage, real account/backend readback and production authorization remain unverified. No CI was queried, triggered or awaited, and no merge, deployment, signing or app release is included.
