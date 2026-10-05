# Native club management: bounded implementation

## Denominator and source contracts

This slice implements 3 of the explicitly inventoried direct actions: approve a join application, reject it, and remove an existing member. It is **not** complete club governance. The first two accept owner / legacy administrator facts from a fresh detail; removal accepts only creator status and a fresh non-creator member row. Both fresh confirmation preparation and immediately-before-dispatch preflight check the same intended action and target. The creator cannot remove their own account even if a row's creator flag is missing.

Verified preserved Flutter files:
- `lib/data/api/club_api.dart`: `/api/club/join-requests`, `/api/club/join-request/approve`, `/api/club/join-request/reject`, `/api/club/remove-member`, numeric JSON `{clubId, memberId}` bodies (read uses `{clubId}`)
- `lib/data/models/club_manage.dart`: `JoinRequest` (`memberId`, `nickname`, `avatar`, `joinTime`)
- `lib/feature/club/club_join_requests_page.dart`: confirmation before approval/rejection; refresh lists after acknowledgment
- `lib/feature/club/club_member_actions.dart`: creator-only removal, creator row protected, remove confirmation
- `lib/feature/club/club_ops_access.dart`: legacy `canGovern` and separate fine-grained access flags

Existing native ClubService supplies source-backed multipart detail/member reads. The new management read requires an explicit array; missing/null/malformed data and duplicate target IDs fail closed rather than becoming an empty authorized list. No endpoints or backend behavior were invented.

## Native behavior

List → application/member detail → native target-specific confirmation sheet. Approval copy explains membership/chat access; rejection copy explains no access and ability to reapply; removal explains club/chat consequences. Confirmation includes club name/ID and member name/ID. Buttons disable during preparation/confirmation/submission; stale or cancelled confirmations cannot dispatch. Lists and permissions are never optimistically modified. Current lists come only from post-write server readback or explicit refresh. Server rejection and success messages are displayed verbatim, with localized fallbacks only when absent.

Account ID, session epoch and token are captured across every multi-step read and write. Identity replacement discards late responses. The session adapter rechecks fresh detail and lists before sending, so stale eligibility causes no write. Cancellation/transport failure after dispatch, 5xx and malformed acknowledgments are uncertain, never automatically retried. The retained coordinator locks that account/club across navigation and epoch changes; a readback cannot prove which write caused current state and cannot unlock uncertainty. Locks are in memory only, not restart-durable or an idempotency guarantee.

## Host integration

1. Retain `ClubManagementSessionAccess` and `ClubManagementCoordinator` with AppSession. Build service only from approved APIConfiguration and existing HTTPTransport; no default host.
2. Current-session closure returns `ClubManagementSession(accountID:epoch:token:)` from the verified session, nil when signed out. Forward unauthorized callback using the existing snapshot-safe expiry mechanism.
3. Call coordinator `synchronizeSession()` on session changes. Expose `ClubManagementView(clubID:identity:access:coordinator:)` from a fresh owner's/admin's club detail; pass the live published identity so the view clears stale content. Invalidate relevant home/detail/member caches through `onMembershipChanged`.
4. DEBUG fixture route: `ClubManagementFixtureScenario.selected(arguments:)` then `ClubManagementFixtureRootView(scenario:)`, before live session construction.
5. Merge `club-management-localizations.json` into String Catalog; regenerate project file to include added sources/tests. The migration branch now wires a retained session owner, fresh-detail management navigation, DEBUG fixtures and shared catalog/project references.

## Explicitly deferred

Fine-grained `/access/me` approver/role grants (narrower legacy-owner/admin coverage is intentional), role promotion/demotion and two-admin limit, temporary bans, full seven-role governance, club creation/profile edits, ownership transfer, dissolution, financial blockers/refunds, compensation, event/registration administration and backend authorization acceptance. No financial mutation exists in this slice.

## Verification

Authored 15 focused pure Swift tests covering exact wire contracts, numeric JSON, invalid-input no-send, owner/admin/ordinary gates, duplicate IDs, server rejection versus uncertain outcomes, token replacement, preflight permission loss, stale/cancelled/double confirmations, session replacement, in-memory locks and readback failure. Authored 6 XCUITests against offline DEBUG fixtures, including target confirmation with zero writes before confirmation, cancel, creator removal, admin restriction and protected creator row. Confirmation queries scope to the native sheet and choose an enabled/hittable leaf for duplicate iOS 26 accessibility wrappers.

Cloud checks: JSON localization parse/coverage and `git diff --check` (including intent-to-add files) pass. Swift/Xcode compilation and simulator tests were **not run here**; no toolchain is available on PATH. Integrated GitHub CI remains required. No live API, signing, commit, push or PR was performed.
