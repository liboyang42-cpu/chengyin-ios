# Social member action factory

## Scope and activation

The normal `AppSession.socialActionAccess` now composes `SocialMemberActionFactory`.
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

## Verification limits

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
