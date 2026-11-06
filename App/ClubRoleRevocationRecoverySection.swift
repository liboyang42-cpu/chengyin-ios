import SwiftUI

/// Current assignments stay in the original list above. Only exact historical audits settle intents.
struct ClubRoleRevocationRecoverySection: View {
    let recovery: ClubRoleRevocationRecovery?
    let context: ClubGovernanceReadContext
    let access: any ClubGovernanceAccess
    let onReceipt: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var history: [ClubRoleRevocationHistory] = []
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
            Text("roleRevoke.history.notice", tableName: "ClubRoleRevocation").font(.footnote).foregroundStyle(.secondary)
            if readable {
                if busy { ProgressView().accessibilityLabel(Text("roleRevoke.loading", tableName: "ClubRoleRevocation")) }
                if issue { Text("roleRevoke.unavailable", tableName: "ClubRoleRevocation") }
                if displayedContext == context {
                    ForEach(history) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: "#\(item.entry.assignmentID) · #\(item.entry.targetMemberID)")
                            Text(verbatim: item.entry.roleCode)
                            Text(LocalizedStringKey(item.entry.outcome == "NOT_SENT" ? "roleRevoke.notSent" : item.receipt?.state == "APPLIED" ? "roleRevoke.applied" : "roleRevoke.unknown"), tableName: "ClubRoleRevocation")
                            Text(verbatim: item.entry.requestID).font(.caption).textSelection(.enabled)
                            if let audit = item.receipt?.auditId { Text(verbatim: "Audit #\(audit)").font(.caption) }
                            if let ms = item.receipt?.appliedAt { Text(Date(timeIntervalSince1970: Double(ms) / 1000), style: .date).font(.caption) }
                        }.privacySensitive().accessibilityIdentifier("club.roleRevoke.history.\(item.id)")
                    }
                }
                Button { refresh &+= 1 } label: { Text("roleRevoke.reconcile", tableName: "ClubRoleRevocation") }
                    .disabled(busy).accessibilityIdentifier("club.roleRevoke.reconcile")
            } else { Text("roleRevoke.unconfigured", tableName: "ClubRoleRevocation").foregroundStyle(.secondary) }
        } header: { Text("roleRevoke.history", tableName: "ClubRoleRevocation") }
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
            guard readable, context == captured, generation == revision, !Task.isCancelled else { throw ClubRoleRevocationFailure.stale }
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
