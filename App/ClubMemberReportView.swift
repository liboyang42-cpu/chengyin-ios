import SwiftUI

/// Only prepares the existing platform-report flow. Target name is display-only;
/// the immutable MEMBER/id anchors use the existing exact governance contract.
@MainActor struct ClubMemberReportView: View {
    let target: ClubMemberReportTarget
    let identity: ClubReadIdentity
    let governance: ClubGovernanceContext
    @Environment(\.dismiss) private var dismiss
    private var currentContext: ClubGovernanceReadContext {
        .init(operation: .members, scope: .init(clubID: target.clubID), identity: identity,
              viewerRevision: governance.viewerRevision, authorizationGeneration: governance.access.authorizationGeneration,
              accessIdentity: ObjectIdentifier(governance.access))
    }
    private var isCurrent: Bool {
        target.context == currentContext && identity == governance.access.identity && governance.access.isConfigured
    }
    var body: some View {
        Group {
            if isCurrent {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("club.memberReport.target").font(.caption).foregroundStyle(.secondary)
                        if let name = target.displayName { Text(verbatim: name).font(.headline) }
                        else { Text("club.memberReport.unnamed").font(.headline) }
                        Text("club.memberReport.explanation").font(.footnote).foregroundStyle(.secondary)
                    }.padding().accessibilityElement(children: .combine).accessibilityIdentifier("club.memberReport.target")
                    ClubGovernanceCommandForm(route: .init(operation: .report, scope: target.scope, seed: target.seed),
                                              identity: identity, access: governance.access, coordinator: governance.coordinator)
                        .id(target.id)
                }
            } else {
                Text("club.gov.changed").onAppear { closeStale() }
            }
        }
        .onChange(of: currentContext) { _, _ in closeStale() }
        .onDisappear { governance.coordinator.cancelReview() }
    }
    private func closeStale() {
        governance.coordinator.cancelReview(); dismiss()
    }
}
