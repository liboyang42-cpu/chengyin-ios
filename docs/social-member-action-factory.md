# Social member action factory

## Scope and activation

The normal `AppSession.socialActionAccess` composes `SocialMemberActionFactory` through
`SocialMemberActionSessionOwner`. The owner retains one access/coordinator pair for
the full runtime context, then selects the current independently supplied approvals
when rebuilding after login, logout, restoration, account, role, epoch, credential
or deployment/realm changes. It observes intermediate states, so returning to an
equal context cannot reactivate a previous review or callback. AppSession deployment
and realm are immutable; changing either requires a new composition/session.

Revoked access has no authenticated identity, no grants, and cannot read or write.
The owner also creates scoped account/Square fallback read bridges whose transport
fences both responses and thrown errors before unauthorized callbacks run. Square
generation routing remains unchanged. Normal composition still blocks every social
route; this lifecycle work neither activates UI nor expands transport permissions.
`NativeRuntimeDependencies.socialMemberActionApprovals` defaults to an empty array.
An endpoint alone cannot activate a write. Each grant covers one operation, one target
member, exact account/epoch/role, namespace, CN market, API base URL, audited path set
and expiry. Duplicate matching grants fail closed. No shipped grant is added.

Supported operations are follow/unfollow and start/get a direct conversation. All
post creation/editing, legacy and community comments, reactions and reports remain
unavailable through this factory. Square generation-aware read routing is delegated
unchanged to the separate read bridge; no community identifier is sent to a legacy
Square endpoint by this factory.

## Source contracts

Verified against the local backend checkout at `f280c988305df257545edc0b48a62d61690ef0e8`:

- `ApiUmsMemberController.getPublicUserInfo`, lines 490–514: POST
  `api/user/public-info`, form `member_id`, current-viewer public profile
- `ApiUmsMemberController.userFollowActoin`, lines 871–936: POST
  `api/user/follow/action`, `follow_member_id` and explicit `follow=0/1`
- `ApiImController.start`, lines 174–195: POST `api/im/start`,
  `target_member_id`, response `data.conversationId`
- `ApiImController.conversations`, lines 30–45, and `ImServiceImpl`, lines
  108–225: POST `api/im/conversations`, direct type 1, current-account
  `counterparty.id`; no fabricated receipt/read route
- `ImServiceImpl.startSingle`, lines 310–343: authenticated caller and
  different positive target, block relationship check and exact single-conversation key
- `ApiCommentController`, lines 115–119 and 362–369: Square legacy writes are
  gated by `legacyCommunityWritesEnabled`; this factory deliberately does not activate them

## Safety and acknowledgement

The review retains the exact member and a full ephemeral runtime-context snapshot.
Account, epoch, role, token, namespace, market or origin changes invalidate it. Before
write, current public-profile state must match the reviewed state. Follow sends the
explicit desired final state, never the old toggle behavior. Checks also run at the
actual transport boundary, after network return and after response decoding.

A durable account/deployment/member lock is written before dispatch. It contains no
token, text, profile or response. It excludes epoch/role/token from the storage key so
relogin cannot bypass an unknown result. Navigation and cancellation fence pending
callbacks. Post-dispatch errors, stale contexts, cancellation and failed readback all
retain the lock; there is no automatic retry or inferred success.

A follow acknowledgement requires both the source response and a fresh profile with
the expected `isFollow` state. Start-chat requires a fresh conversation list containing
the exact returned ID, direct-conversation type and reviewed counterparty. Only that
verified same-session result clears the lock and returns a nonsynthetic receipt.

## Lifecycle coverage and verification limits

Authored lifecycle XCTest coverage adds guest-first access followed by exact-grant
login, stable same-context retention, role/account/epoch/token/namespace/market/origin
replacement, observed A→B→A revocation, delayed prepare/preflight/write/readback,
late 401 suppression (including fallback reads), current fallback 401 handling,
Square generation preservation, and current approved follow/chat acknowledgement.
A rebuilt or relaunched owner finds the same canonical unknown lock. Account and
realm separation are checked without changing the persisted key or clearing records.

App-hosted tests cover normal composition guest-first login/logout/relogin,
authenticated role/account replacement, restoration and existing unknown journals,
realm separation, and social transport rejection even with an exact synthetic grant.
These are authored tests, not evidence of Apple execution.

## Other verification limits

New Core XCTest coverage calls the same factory used by AppSession with injected HTTP
transport, not a synthetic access implementation. It covers default-OFF, exact follow
payloads, chat readback, target/action separation, stale reviews, cancellation, duplicate
submission, relaunch/relogin persistence, wrong origin/market/namespace/role/epoch,
token-only changes, and role/namespace changes during final readback. An AppUnit test
constructs normal AppSession and verifies shipped member-write grants remain absent.

Linux source contracts, Swift tree-sitter parsing, project generation and patch
reapplication are separate checks. Apple compilation, XCTest execution, device/UI
behavior, endpoint deployment and live business acceptance remain pending. No live
request, device permission, account operation, legal acceptance or production grant
was exercised or enabled.
