# Club meeting-time and contextual-review normal factories

## Scope and activation

The existing normal `clubGovernanceContext.opsTimeFactory` and contextual review callers now receive configured wrappers from two independent, optional `NativeRuntimeDependencies` inputs. Both default to nil. There are no plist switches, deployment approvals, credentials, new backend routes or live requests in this change.

The previous HTTP adapters already implemented the transport contracts. Their normal callers always selected `enabled: false`. This change closes that composition gap rather than claiming a missing server endpoint was added. Legacy adapter constructors remain available for existing synthetic tests; normal app construction uses the stricter wrappers.

## Source-backed contracts

Rechecked against the current supplied backend source, with byte hashes in the integration packet:

- `ApiActivityController.activityInfo`: POST `api/activity/info`, form `id`; returns the exact activity ID, club ID, start time and `timeLocationLocked`. The lock includes pending/unpaid, paying and paid registrations. A club access-gate response is not a full activity.
- `ApiClubLeadController.teamProgress`: GET `api/club/lead/team-progress?activityId=...`; confirms `exists`, `isLeader` and the resolved `leaderMemberId`. This source route can lazily initialize/update its lead-state projection; it is not an invented permission service.
- `ApiClubLeadController.editOps`: POST `api/club/lead/edit-ops`, JSON containing only `activityId` and `startDate`. Current leader and sold-time/place restrictions are independently enforced server-side. Its success records an edit/log acknowledgment, not guaranteed notification delivery.
- `ApiCommentController.addComment`: POST `api/comment/add`, exact existing form fields: `owner_type`, `owner_id`, `rating`, `contents`, `reply_id=0`, `img_arr` empty. Owner type 1 is topic; 2 is activity. The inserted comment is returned as `data`.
- `CommentPublicationService.publish`: topic/activity must exist. Paid/verified participation affects first-review rewards, not eligibility to post an ordinary review. The native factory therefore does not invent a paid-registration requirement or reward acknowledgment.
- Topic preflight uses existing POST `api/topic/info-to-user`, form `id`; activity preflight uses `api/activity/info`. Both must return the exact accessible target. Post-write comment receipt checks its ID, account, owner type, target, reply, rating and trimmed content. Existing detail callers separately refresh after acknowledgment.

## Authorization and lifecycle

Approval binds CN market, exact base URL, account, storage namespace, required endpoint paths and typed target. Meeting-time grants additionally bind activity to club; conflicting club grants for one activity are invalid. Review target kinds never alias equal integer IDs.

Each operation captures market, deployment, namespace, account, role, epoch and credential. Captured UI sessions carry that complete context. Checks happen before and after every read and write. A replacement session cannot receive a stale result or a late unauthorized-expiration callback.

Normal coordinators require a durable journal before dispatch. The journal stores only account/deployment/namespace/target, local operation ID and acknowledgment count, never review text, times, tokens or response data. A single-use authorization binds the exact command to that pending record. Direct configured-writer calls without coordinator authorization fail closed. A journal failure sends no mutation.

Unknown outcomes stay locked across navigation, host recreation and same-account epoch changes. Meeting-time readback cannot clear an unknown lock. Acknowledged reviews remain locked against duplicate submission. Preflight failure and definitive delivered business rejection may be reviewed and attempted again; both repeat fresh checks. Cancelling after mutation dispatch is unknown, not an inferred rollback.

## Verification boundary

This packet adds 19 pure Swift tests and two app-unit tests covering default-off construction, exact authorization, source scope, durable replay, cancellation, stale sessions, receipts and readback. Existing synthetic constructor tests remain in place.

Local Python contracts, tooling tests, scaffold regeneration and supplementary Tree-sitter parsing are separate evidence in the packet. This Linux workspace has no Swift/Apple toolchain: Swift execution, app compilation, app-unit runtime, simulator/device, live backend and provider acceptance are NOT_RUN here. Production activation remains OFF. Full framework upgrades, World/Season, maps and unrelated factories are outside this change.
