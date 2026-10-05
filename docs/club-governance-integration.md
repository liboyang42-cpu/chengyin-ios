# Parent integration handoff

The additive module originated in `native-club-governance-new` and was integrated after the parent assigned the shared slot (2026-10-01 21:26 UTC). The steps below record the integration contract; shared mounting, catalog merge and project regeneration are now applied locally. Copy the additive Core/ClubGovernance*.swift, App/ClubGovernance*.swift, Tests/CoreTests/ClubGovernance*.swift and Tests/AppUITests/ClubGovernanceFlowTests.swift into the corresponding target folders. Copy tools/check_club_governance.py and these documents; merge Resources/ClubGovernanceLocalizations.fragment.json `strings` into Localizable.xcstrings without replacing unrelated entries.

## Shared edits needed

1. AppSession: add an optional ClubGovernanceService initialized alongside clubOperationsService using the already approved configuration and transport. Set nil in the unconfigured branch. Use only the normal constructor; never the offline-writing initializer.
2. Add `currentClubGovernanceSession` with account.id, gate.currentStamp, current token, and storageScope?.service namespace. Add a lazy ClubGovernanceSessionAccess with the live-session closure and an unauthorized callback that verifies account/epoch against the current captured identity before calling expireIfMatching. Add one AppSession-lived ClubGovernanceCoordinator and a ClubGovernanceContext containing that access/coordinator. Do not create a coordinator per view: unknown locks must survive navigation.
3. ClubManagementContext: add `var governance: ClubGovernanceContext? = nil`. Pass `governance: clubGovernanceContext` in AppSession's existing clubManagementContext factory. All directory/owned/search/detail callers already forward management, so this is additive.
4. ClubHomeView: in the initial Section, add ClubGovernanceHomeEntries with reader.clubIdentity and the optional management.governance dependencies. This makes host application and joined-club feed reachable.
5. ClubDetailView: add a Section containing ClubGovernanceEntryButton for optional management.governance. Place it OUTSIDE `(club.isOwner || club.viewerIsAdmin)` so delegated event staff and fine-grained roles can enter. The workspace reads access/me and enforces each action's permission itself.
6. DEBUG QuestifyApp: add `--uitesting-club-governance` → ClubGovernanceFixtureHost, and add the same flag to AppSessionContainer's fixture exclusion guard. No normal AppSession should be created in fixture mode.
7. Call coordinator.cancelReview() on session invalidation/namespace changes alongside existing operation coordinators. This invalidates pending reviews but intentionally preserves scoped unknown locks.
8. Run tools/generate_project.py after copying files; then check_scaffold.py, check_club_governance.py and the pinned syntax checker. The parent must rerun the aggregate final-byte checks after all concurrent batch integration.

## Apple-toolchain stage

When an approved Apple environment is available, run swift test, unsigned CN/US simulator/device builds and ClubGovernanceFlowTests. The tests assume the DEBUG fixture selector is mounted and the fragment merged. None has run in this workspace. Fix compiler/actor/SwiftUI runtime issues before changing this status.

UI manual scenarios: member vs owner vs co-owner/operator vs event-only lead/check-in, missing/bad access vs explicit denial, permission revoked during review, two club IDs in one session, unknown send then close/reopen, same account/new epoch, another storage namespace, roster missing correction version, partial refund manual orders, null audience count, unknown/void settlement, English/Chinese, maximum text size, VoiceOver, Back/Close/discard, group-code expiry and stale-image handling.
