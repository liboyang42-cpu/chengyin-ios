import SwiftUI

/// Mini pages/club/join-requests and pages/club/notify copy. Display only: every action stays the
/// existing review/claim flow and every retry is the existing read refresh.
struct ClubOpsJoinRequestActionLabel: View {
    let action: ClubManagementAction
    let progressKey: String?
    var body: some View {
        if let progressKey {
            Text(LocalizedStringKey(progressKey), tableName: "ClubOpsJoinNotify")
                .accessibilityIdentifier("clubOpsJoin.progress." + action.rawValue)
        } else {
            Text(LocalizedStringKey("club.management." + action.rawValue))
        }
    }
}

struct ClubOpsJoinRequestLoadIssue: View {
    let issue: ClubOpsJoinRequestCopy.LoadIssue
    let disabled: Bool
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue == .failed ? "clubOpsJoin.failed" : "clubOpsJoin.stale", tableName: "ClubOpsJoinNotify").font(.headline)
            Button(action: retry) {
                Text(issue == .failed ? "clubOpsJoin.retry" : "clubOpsJoin.retryStale", tableName: "ClubOpsJoinNotify")
            }
            .buttonStyle(.borderless).disabled(disabled)
            .accessibilityIdentifier(issue == .failed ? "clubOpsJoin.retry" : "clubOpsJoin.retryStale")
        }.accessibilityIdentifier(issue == .failed ? "clubOpsJoin.failed" : "clubOpsJoin.stale")
    }
}

/// Mini notify `no-permission` state: no retry, because repeating the read cannot grant access.
struct ClubOpsNotifyDeniedText: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("clubOpsNotify.denied.title", tableName: "ClubOpsJoinNotify").font(.headline)
            Text("clubOpsNotify.denied.body", tableName: "ClubOpsJoinNotify").font(.footnote).foregroundStyle(.secondary)
        }.accessibilityIdentifier("clubOpsNotify.denied")
    }
}

/// Page-level failure title for notify / governance / roles reads; the retry is the read view's own `load()`.
struct ClubOpsPageFailureSection: View {
    let copy: ClubOpsPageFailureCopy
    let retry: () -> Void
    var body: some View {
        Section {
            Text(LocalizedStringKey(copy.titleKey), tableName: copy.table).font(.headline)
                .accessibilityIdentifier("clubOps.pageFailure.title")
            Button(action: retry) { Text(LocalizedStringKey(copy.retryKey), tableName: copy.table) }
                .accessibilityIdentifier("clubOps.pageFailure.retry")
        }
    }
}

#if DEBUG
/// Offline-only switches for the club-ops states (no network, no account). Each one only edits the synthetic access.
@MainActor struct ClubOpsFixtureControls: View {
    let access: ClubGovernanceFixtureAccess
    var body: some View {
        Button { access.writeFailure = .conflict(message: nil) } label: { Text(verbatim: "Fixture: next write returns 409") }
            .accessibilityIdentifier("clubOps.fixture.conflict")
        Button { access.permissionValue = Self.permissions(removing: ["club:notify:send", "club:event:operate"]) } label: { Text(verbatim: "Fixture: no notify permission") }
            .accessibilityIdentifier("clubOps.fixture.notifyDenied")
        Button { access.readFailure = .malformed } label: { Text(verbatim: "Fixture: reads fail") }
            .accessibilityIdentifier("clubOps.fixture.readFailure")
        Button {
            access.permissionValue = ClubGovernanceFixtures.json(#"{"active":false,"club":{"id":81},"roleCodes":[],"permissions":[]}"#)
            access.overrideValue[.cases] = ClubGovernanceFixtures.json(#"{"data":[{"id":172,"clubId":81,"caseType":"APPEAL","targetType":"BAN","targetId":161,"status":"PENDING","version":0,"reason":"Fixture appeal"}],"activeBan":{"id":161,"clubId":81,"status":"ACTIVE","sourceType":"CLUB","banReason":"Fixture reason","bannedAt":"2026-10-01 09:00:00","expiresAt":"2026-10-31 09:00:00"}}"#)
        } label: { Text(verbatim: "Fixture: banned viewer appeals") }
            .accessibilityIdentifier("clubOps.fixture.bannedAppeal")
        Button {
            access.permissionValue = ClubGovernanceFixtures.permissions; access.overrideValue[.cases] = nil
            access.readFailure = nil; access.writeFailure = nil
        } label: { Text(verbatim: "Fixture: reset club-ops states") }
            .accessibilityIdentifier("clubOps.fixture.reset")
    }
    static func permissions(removing removed: Set<String>) -> ClubGovernanceValue {
        guard var object = ClubGovernanceFixtures.permissions.object else { return ClubGovernanceFixtures.permissions }
        object["permissions"] = .array((object["permissions"]?.array ?? []).filter { !removed.contains($0.string ?? "") })
        return .object(object)
    }
}
#endif
