import SwiftUI

/// Current assignments stay in the original list above. Only exact historical audits settle intents.
struct ClubRoleAssignmentRecoverySection: View {
    let recovery: ClubRoleAssignmentRecovery?
    let context: ClubGovernanceReadContext
    let access: any ClubGovernanceAccess
    let onReceipt: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var history: [ClubRoleAssignmentHistory] = []
    @State private var displayedContext: ClubGovernanceReadContext?
    @State private var visible = false
    @State private var busy = false
    @State private var issue = false
    @State private var refresh: UInt64 = 0
    @State private var generation: UInt64 = 0
    private struct Trigger: Hashable { let context: ClubGovernanceReadContext; let visible: Bool; let active: Bool; let refresh: UInt64 }
    private var readable: Bool { visible && scenePhase == .active && access.identity == context.identity && access.authorizationGeneration == context.authorizationGeneration && recovery?.canRead(scope: context.scope, identity: context.identity) == true }
    var body: some View {
        Section {
            Text("roleAssign.history.notice", tableName: "ClubRoleAssignment").font(.footnote).foregroundStyle(.secondary)
            if readable {
                if busy { ProgressView().accessibilityLabel(Text("roleAssign.loading", tableName: "ClubRoleAssignment")) }
                if issue { Text("roleAssign.unavailable", tableName: "ClubRoleAssignment") }
                if displayedContext == context {
                    ForEach(history) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: "#\(item.entry.targetMemberID)")
                            Text(verbatim: item.entry.roleCode)
                            Text(LocalizedStringKey(item.entry.outcome == "NOT_SENT" ? "roleAssign.notSent" : item.receipt?.state == "APPLIED" ? "roleAssign.applied" : "roleAssign.unknown"), tableName: "ClubRoleAssignment")
                            Text(verbatim: item.entry.requestID).font(.caption).textSelection(.enabled)
                            if let assignment = item.receipt?.assignmentId { Text(verbatim: "#\(assignment)").font(.caption) }
                            if let audit = item.receipt?.auditId { Text(verbatim: "Audit #\(audit)").font(.caption) }
                            if let ms = item.receipt?.appliedAt { Text(Date(timeIntervalSince1970: Double(ms) / 1000), style: .date).font(.caption) }
                        }.privacySensitive().accessibilityIdentifier("club.roleAssign.history.\(item.id)")
                    }
                }
                Button { refresh &+= 1 } label: { Text("roleAssign.reconcile", tableName: "ClubRoleAssignment") }
                    .disabled(busy).accessibilityIdentifier("club.roleAssign.reconcile")
            } else { Text("roleAssign.unconfigured", tableName: "ClubRoleAssignment").foregroundStyle(.secondary) }
        } header: { Text("roleAssign.history", tableName: "ClubRoleAssignment") }
        .onAppear { visible = true }
        .onDisappear { visible = false; generation &+= 1; history = []; displayedContext = nil }
        .onChange(of: context) { _, _ in generation &+= 1; history = []; displayedContext = nil }
        .onChange(of: scenePhase) { _, phase in if phase != .active { generation &+= 1; history = []; displayedContext = nil } }
        .task(id: Trigger(context: context, visible: visible, active: scenePhase == .active, refresh: refresh)) { await restore() }
    }
    @MainActor private func restore() async {
        generation &+= 1; let revision = generation, captured = context
        history = []; displayedContext = nil; issue = false; busy = false
        guard readable, let recovery else { return }; busy = true
        func check() throws {
            guard readable, context == captured, generation == revision, !Task.isCancelled else { throw ClubRoleAssignmentFailure.stale }
        }
        do {
            let values = try await recovery.history(scope: captured.scope, identity: captured.identity, access: access, check: check)
            try check(); history = values; displayedContext = captured; busy = false
            if refresh > 0 { onReceipt() }
        } catch {
            guard generation == revision, context == captured, readable, !Task.isCancelled else { return }
            history = []; displayedContext = nil; busy = false; issue = true
        }
    }
}
