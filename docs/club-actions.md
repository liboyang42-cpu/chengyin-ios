# Native club membership actions

## Source and scope

Read-only reference: `app-audit/lib/data/api/club_api.dart` (`join`/`quit`, lines 111–136), `lib/data/models/club.dart` (`isOwner`, `isJoined`, `joinPolicy`, `myJoinStatus`, lines 1–149), and `lib/feature/club/club_detail_page.dart` (`_toggle`, `_ClubHeader`, approximately lines 101–133 and 337–411).

- Join and application: multipart `POST api/club/join`, field `id` as a string
- Leave: multipart `POST api/club/quit`, field `id` as a string
- Both require a numeric business `code: 200`; `msg` is retained as a server message
- Join may return `data.state`. `joined`, `pending`, absent, and unknown states remain distinct receipt values. None grants membership locally
- Fresh `POST api/club/detail` with multipart `id` returns the actual membership, member count, owner status, and pending application state
- Source owners cannot leave; signed-in existing members can leave. Non-member merchants get the source partnership-oriented gate instead of Join. Pending applications cannot be submitted again. Rejected applications can reapply. Viewer administrator status does not grant owner privileges
- Unknown numeric join status is conservatively disabled. The existing read contract retains the source's normalization of joinPolicy to 0 or 1

The inspected club model/detail/API flow has no membership payment initiation contract. This implementation adds no payment/fee bypass, automatic approval, management, dissolution, invite, or credential behavior. If a service requires payment or rejects a request, the response stays a rejection/unknown result; there is no alternate join path. Create/edit are excluded from this bounded slice so hidden source fields cannot be dropped by a partial form.

## Integration API

The root/session owner must retain ONE `ClubActionCoordinator` across club-detail navigation, with a `ClubActionSessionWriter` and the same `ClubReading` identity provider. The writer accepts `ClubActionService?` and `currentSession: () -> ClubActionSession?`. Construct a session from the verified `Account`, session epoch, and token. Advance the epoch on every logout, account/token replacement, and same-account relogin. No role chooser value may substitute for the verified Account.

`ClubActionService(configuration:transport:)` needs an explicitly approved configuration and the existing no-redirect transport; this slice does not instantiate either. `onUnauthorized` receives the exact captured session and must expire only that still-current session. The coordinator's optional `onMembershipChanged(Int)` callback lets the owner invalidate club/home/member caches after acknowledgment.

Pass `actionCoordinator:` into `ClubDetailView`. It defaults to nil, leaving existing read-only paths and fixtures unchanged. A native confirmation states the fresh club name and Join/Apply/Leave consequences. Fresh detail is fetched both before confirmation and immediately before mutation. Changed policy or membership cancels the original intent; a stale Join never becomes Leave automatically.

The native detail orders both ordinary refreshes and action readbacks using one screen generation. The coordinator’s optional `onReadbackStarted`/`onStarted` notifications establish the actual read-start boundary; an older completion cannot replace a newer refresh in either direction. Screen-owner UUIDs also prevent an old detail screen from cancelling a newer screen’s confirmation or readback.

The root owns root navigation, session adapter construction, project generation, and String Catalog merge. Add the entries from `docs/club-actions-localizations.json` to the shared catalog. The original isolated slice left those shared files untouched. The integration in `chengyin-ios` now retains the session writer/coordinator, forwards it through home/directory/owned entry points, merges the 24 strings, and generates the project. The root task owns the three `QuestifyApp.swift` insertions (fixture branch, fixture session-construction exclusion, and normal home coordinator injection).

## Safety and result model

- Only an explicit confirmation dispatches one mutation; repeated preparation/confirmation is guarded
- ID, account, epoch, token, and current server rights are checked. The UI carries no token
- Acknowledgment triggers one detail readback. Member counts, member-list eligibility and pending status come from that detail, never from optimistic arithmetic or `data.state`
- Unknown transport/malformed/cancelled/HTTP outcomes do not retry, poll, or auto-read; a user can explicitly read current membership
- Unknown-outcome locks remain per account and club in memory across screen dismissal and same-account relogin; readback does not clear them or claim proof of an earlier request's outcome. Other accounts never see old receipts or readback. Another club is independent
- Dismissing while a request is in flight marks the local result unknown. It does not claim the server cancelled. A late success cannot unlock it; a writer-proven no-send preflight or definite rejection can safely clear that record without replay
- Locks are in memory, not durable backend idempotency. App restart loses them. Source contract contains no idempotency key or operation-status endpoint
- Server membership changes between the final read and POST still rely on server authorization. Client checks do not replace it

## Offline fixtures and test coverage

`ClubActionFixtureScenario.selected(arguments:)` accepts `--uitesting-club-action-fixture` followed by `join`, `apply`, `leave`, `pending`, `owner`, `merchant`, `reapply`, `denied`, `unknown`, `readbackUnavailable`, `delayed`, `guest`, or `refreshConsistency`. Root can route to `ClubActionFixtureRootView(scenario:)` inside DEBUG. No fixture creates transport, host, token, or persistent data.

The unknown fixture changes synthetic server membership and then loses the receipt. Readback shows Joined while the unknown lock remains, demonstrating why current membership and acknowledged mutation are different. Fixture controls support sign-out/account switching and a visible mutation counter. Delayed dispatch supports interruptions/repeated-tap tests. The `refreshConsistency` fixture joins successfully, then simulates server-side removal on the next ordinary refresh; header, action and readback badge must all return to not-joined even though that refreshed record equals the original pre-join snapshot.

50 new pure tests cover exact wire routes/fields, receipt-state separation, rejection/unknown classification, no retries, strict session guards before/after detail and dispatch, rights changes, owner/merchant/admin/pending gates, duplicate taps, fresh membership readback, callback behavior, stale/wrong-club results, interrupted preparation/write/readback, and per-account/club locks.

Validation performed in this cloud Linux worktree: source-contract inspection, six existing Python tests, diff checks, and a temporary-copy integrated scaffold check (111 Swift source references, 676 bilingual keys, valid project/scheme references and deterministic regeneration). The temporary copy merged the localization additions and generated the project; shared project/catalog files in this worktree remain untouched. No Swift/Xcode toolchain is available here; tests and iOS compilation are authored but not executed in this worktree. Root's macOS verification is required. No live API requests, membership changes, credentials, commits, pushes, or user-computer operations were performed.

## Root integration verification

The `chengyin-ios` integration adds `Tests/AppUITests/ClubActionFlowTests.swift` with three offline cases: Join confirmation and server readback; Apply remaining pending without member-list access; unknown-outcome readback and lock persistence across same-account relogin. Existing UI tests are unchanged. AppSession's unauthorized callback compares the full current/captured `ClubActionSession` before expiry, including epoch, account, credential and merchant-role status. The retained coordinator is synchronized at each existing session transition; a definite no-send/rejection remains distinct from an unknown dispatched outcome even when expiry synchronization runs during the callback.

Root structural checks pass with 121 Swift source references and 760 bilingual keys; six Python tests and whitespace checks pass. Swift domain tests and the three simulator cases remain authored but unexecuted in this Linux environment. Shared root changes in `MessageActionComposer.swift` and `QuestifyApp.swift` were preserved and not edited by the club integration worker. No commit, push, configuration edit, or live API request occurred.
