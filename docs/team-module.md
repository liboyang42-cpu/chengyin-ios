# Owned teams, invitation review and activity-team creation

Status: source-backed native slice; normal AppSession now supports an explicitly injected, revocable team-read lease. Its selector defaults to nil; normal release startup remains unconfigured and all live writes/sharing are disabled. No backend call or actual team operation was performed. Swift/Xcode/runtime NOT_RUN.

## Implemented

- Account and ticket-wallet “My teams” navigation to an authenticated owned-team list, fresh detail and member roster
- Distinct recruiting/full/in-progress/ended/disbanded/unknown status presentation; source joinedCount, maxMembers and expireTime remain independent of roster length and startTime
- Native local invitation preview, invitation-target detail/join review, already-joined handling and invalid-link recovery
- Activity-team creation form and immutable review, using source registration eligibility and 2–4-person size choices; default public mode omits joinMode while invitation-only describes joinMode:1
- Reviewed leave, member removal and dissolution, including ticket/refund/chat consequences and “Leave instead” from dissolution review
- Missing membership, captain, join mode, count, time or status remains unknown. Roster ordinary-member role is 0; captain is 1. Unknown roles cannot authorize removal
- Shared card composition, system symbol fallback instead of invented artwork, scalable text, semantic status/labels, 44-point actions, native stack/form/sheet navigation
- Synthetic DEBUG fixtures for list, detail, invitation, creation, empty/failure/retry, guest/unconfigured, status variants, missing roles, rejected/not-sent/unknown outcomes; 74 English/zh-Hans keys

## Source contract evidence

Source root for local audit: preserved Flutter `app-audit`.

| Native area | Source |
| --- | --- |
| Owned teams | `lib/data/api/team_map_api.dart`, `myTeams`: POST `/api/team/my`, empty payload, array of owned/member teams; preserve ownerType/ownerId |
| Detail and invitation | `lib/data/api/page_parity_api.dart`, `teamInfo`: POST `/api/team/info` with teamId OR inviteCode; invitation page additionally permits flat data |
| Invitation join descriptor | `page_parity_api.dart`, `teamJoin`: POST `/api/team/join`, inviteCode only |
| Create descriptor | `team_map_api.dart`, `createActivityTeam`: POST `/api/team/create`, ownerType:2, ownerId, maxMembers, optional joinMode:1; positive returned teamId required |
| Removal/leave/dissolution descriptors | `page_parity_api.dart`, `teamAction`: `/api/team/kick` {teamId,memberId}, `/api/team/quit` {teamId}, `/api/team/disband` {teamId} |
| UI, status and consequences | `lib/feature/team/team_pages.dart`; `test/feature/team/team_pages_test.dart` verifies five statuses, expireTime, joinedCount and roster role 0/1 |
| Creation eligibility and size | `lib/feature/orders/order_detail_sheet.dart`: ownerType==2, registrationStatus==2, teamMode==2; clamp maxMembers into 2...4 |
| Wallet ownership | `lib/feature/tickets/tickets_page.dart`: ownerType:ownerId index, distinct from teamId; excludes ended/disbanded |

The normal live factory still contains only two read routes. Descriptors do not construct URLRequests or perform writes. The earlier Flutter inference limitation for join-mode is superseded by the pinned mini-app and backend contract documented below; its guarded adapter remains dormant without an exact endpoint approval.

## Safety and evidence limits

TeamSession captures account, epoch, server role, region, deployment storage namespace and private credential. Current session and generation are checked after every await; changed routes, account/epoch/role changes, cancellation and stale reads invalidate reviews/results. Current 401 callbacks are matched before the parent expires a session; server exception text or URLs never become UI copy.

Review captures the exact action and baseline. Confirmation consumes that review once, re-reads the same target/invitation or creation context, compares complete fresh facts, and checks the pending journal again. Synthetic submission writes the minimal pending record before dispatch. A journal failure blocks submission. Unknown outcomes cannot be retried by refreshing, reopening, creating a second coordinator or reauthenticating the same account. Records are scoped to region/deployment/account/target, not epoch, and contain no credentials, invitation codes or roster data. Normal UserDefaults persistence/reconstruction is tested; power-loss durability has not been established.

An ordinary list/detail refresh does not prove whether a mutation finished. A known immediate acknowledgment or an operation-correlated synthetic terminal receipt can clear its pending record. No production receipt/reconciliation/idempotency endpoint has been invented. AppSession's default TeamReadOnlyService is intentionally constructed without configuration. The factory now accepts an optional scoped read grant and an owned registration source; both remain absent. A separate dormant TeamHTTPService implements exact create/join/quit/kick/disband and join-mode requests only with explicit approval and a persisted local operation. It never replays a dispatch-start marker. See [operation adapters](operation-adapters-module.md).

Native removal is conservatively restricted to recruiting/full teams and explicit ordinary-member role 0; Flutter displays the removal control more broadly. Native missing roles/statuses fail closed rather than using Flutter's permissive defaults. Unzoned expireTime is displayed as supplied, with no fabricated timezone/countdown. Public guest invitation reads, remote avatars, share sending and universal links are not connected.

## Remaining migration work

- Nearby teams, map filtering/location, public applications, withdrawal, captain application review and my-applications are a separate source domain and are not implemented by this slice
- Native orders currently do not yet expose source teamMode/teamMaxMembers; therefore production creation entry cannot infer eligibility from a ticket or activity ID. The order-lifecycle worker has the typed TeamCreationContext contract for a later fresh-registration adapter
- SessionTeamDetailView and SessionTeamCreateView are integration adapters, not universal-link or order-eligibility implementations
- Actual invitations, membership changes, dissolution, notifications, team chat, creator state updates, terminal receipts and backend idempotency need verified contracts and explicit release acceptance
- No payment, refund, ticket issuance or redemption is implemented or implied; owned-team IDs, activity owners, route owners and ticket IDs remain distinct
- Physical-device, VoiceOver, Dynamic Type layout, dark mode and visual acceptance remain pending Apple execution

## Integration

All eight primary Core/App files, SessionTeamViews, two CoreTests files and TeamFlowTests are integrated in the parent repository; the isolated handoff is `native-team-flows-new`. Resources/TeamLocalizations.fragment.json is merged into Localizable.xcstrings. ModuleFixture.teams opens TeamFixtureHostView before production AppSession construction. Account exposes SessionTeamHomeView; TicketWalletView accepts an optional coordinator factory for its distinct My teams link.

AppSession owns one minimal pending journal and constructs route-specific coordinators. Session wrappers are keyed by epoch/account/role/market, and currentTeamSession also includes the reviewed regional storage namespace. Keep these guards if adding fresh-registration creation context. Never resolve an activity by treating registrationID or teamID as ownerID.

For a future source order adapter, derive TeamCreationContext only from the current account's exact registration read. Preserve registration ID separately for preflight, assert ownerType==2 and ownerId>0, and require registrationStatus==2/teamMode==2. Passing a context alone must not enable dispatch.

## Default-off normal-runtime read wiring (2026-10-04)

`AppCompositionRoot.teamReadApproval` defaults to nil. The typed, expiring `TeamReadApproval` binds CN origin/base path, storage namespace (including bundle/realm), current account, token, epoch and role. Normal TeamSession and retained coordinator checks additionally carry viewer revision, so role ABA cannot reuse stale results. Outer transport checks exact canonical POST JSON `api/team/my {}` and `api/team/info {teamId}` or `{inviteCode}` before dispatch and rechecks lease revision/context after success or error. Transport clones retain that selector. No authentication/RBAC changes or production grant issuer were added.

The normal factory passes only the lease’s two read paths to TeamReadOnlyService. It requires fresh `joined == true` for ID detail, preserves nonmember invitation detail, and never constructs TeamHTTPService. The root rejects create/join/quit/kick/disband/join-mode and other adjacent routes. Owned registration creation lookup remains separately gated. Revoked/replaced leases make an existing normal coordinator’s captured session unavailable rather than adopting new authority. The team journal uses the existing composition defaults and unchanged ownerKey; reads and logout do not clear unknown-operation records.

Private source verification at commit `11be8cb2f09073496f3a7d5130d558da60cf5439`: ApiPlayTeamController blob `c55319d052398b92e971d8cc07adb0a68e2fd468` exposes my via current member and info via teamId/inviteCode/current optional member. PlayTeamServiceImpl blob `342120fe1e42e75760a481ed52c35cac07dbe399` requires a valid member for my, active team membership for ID lookup, and available invitation for code lookup. This does not establish deployment readiness.

Authored acceptance: TeamReadApprovalTests, TeamReadCompositionTests, and the sealed integrated normal-root Team UI journey. All network/storage data are synthetic, selected through the existing DEBUG fixture. Syntax/scaffold/Python contracts do not execute Swift: Apple compilation, Core/App XCTest and UI execution remain UNRUN until exact-candidate Apple verification. No deployment origin, credential, login, provider, production gate or configuration was changed.


## Captain join-mode source group (2026-10-19)

Verified backend/mini baseline: `57b22916e05e0c7eccccb75f68a46a4576ab5bf8` in private `liboyang42-cpu/chengyin` (read-only evidence; no backend edits).

- Mini `chengyinhub-xcx/pages/team/detail/index.js`, `onJoinModeChange`: captain + recruiting status 0, POST JSON `/api/team/join-mode` with exactly `teamId` and numeric `joinMode` 1/2; consumes `data.joinMode`.
- Controller `chengyinhub-admin/src/main/java/com/chengyinhub/web/controller/api/ApiPlayTeamController.java:58–71`: authenticated member, returned mode only. No team ID, operation ID or remote receipt.
- Service `chengyinhub-system/src/main/java/com/chengyinhub/business/service/impl/PlayTeamServiceImpl.java:128–138`: require current captain under team lock, validate mode 1/2, same-value no-op, update via team/captain IDs. Native preserves the stricter mini recruiting gate.
- Mapper `chengyinhub-system/src/main/resources/mapper/business/PlayTeamMapper.xml:62–65`: update is keyed by team ID and leader member ID.

Normal My teams → exact detail → choose a different known mode → immutable review → explicit confirm uses the existing coordinator and team-target journal. The normal root remains read-only, so it can prepare a review but cannot dispatch. Offline fixtures simulate the complete outcome separately.

Both coordinator and adapter reread membership/captain/status before submission. The coordinator freezes full detail; unknown/current-same mode, noncaptain, nonmember, nonrecruiting, read-only post-join continuation and pending intent deny mode changes. Request body contains no fabricated operation key. Numeric returned mode must equal the reviewed mode; missing, Boolean, string, fractional, unknown or mismatched values leave outcome unknown.

Typed mode acknowledgment is locally bound to the captured operation and team; it does not claim server-returned correlation. The journal persists only an additional optional numeric join-mode discriminator; old non-mode records decode with nil. Generic success cannot clear a mode operation, including after coordinator reconstruction. Only a matching typed response and successful journal clear display confirmed mode. Full roster/detail is never synthesized from that response. Another change requires a fresh full detail read. A matching later current mode does not reconcile an unknown operation or clear its lock. There is no automatic retry or live receipt endpoint; the existing receipt check is synthetic-only.

The fixture changes only mode while preserving roster and other detail fields. Existing create/join/leave/remove/disband and their departure/read-only guarantees remain separate. No global localization catalog, normal composition grant, production write, payment, reward, registration or sharing activation changes.

Validation status: source/structure review and authored synthetic tests only. Swift compilation, Core/App/UI tests and real App behavior have not been run for this group. Not a claim of a complete original master-document requirement or release readiness.
