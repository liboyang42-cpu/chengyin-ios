import SwiftUI

@MainActor struct NativeChannelAuditEntry: View {
    let channels: any NativeChannelManagementIntegrationContextProviding
    let channelID: NativeChannelManagementID
    let makeFlow: (NativeChannelManagementIntegrationContext) -> NativeChannelAuditFlow?
    @State private var flow: NativeChannelAuditFlow?
    @State private var unavailable = false
    @State private var generation = 0
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let flow, flow.isCurrent {
                List {
                    if flow.source == .lifecycle {
                        if !flow.operations.isEmpty {
                            Section {
                                ForEach(flow.operations) { row in
                                    NativeChannelAuditRow(action: row.action, actor: row.operatorID, date: row.createdAt, reason: row.reason)
                                }
                            }
                        }
                    } else {
                        Section("d7.channelAudit.integrity") {
                            Button("d7.channelAudit.verify") { Task { await flow.verifyOriginalChain() } }.disabled(!flow.canVerify)
                            if let proof = flow.verification {
                                LabeledContent("d7.channelAudit.result") {
                                    Text(proof.chainOK ? LocalizedStringKey("d7.channelAudit.intact") : LocalizedStringKey("d7.channelAudit.notVerified"))
                                }
                                LabeledContent("d7.channelAudit.checked", value: String(proof.checkedRows))
                                if proof.unprovenOriginalRows > 0 { LabeledContent("d7.channelAudit.unverified", value: String(proof.unprovenOriginalRows)) }
                                if !proof.linkedProjectionOK { Text("d7.channelAudit.hiddenUnverified").foregroundStyle(.secondary) }
                                if proof.frozen { Text("d7.channelAudit.frozen").foregroundStyle(.secondary) }
                                if proof.anchorEvidence != nil {
                                    LabeledContent("d7.channelAudit.backups") {
                                        Text(proof.externallyAnchored ? LocalizedStringKey("d7.channelAudit.backupsComplete") : LocalizedStringKey("d7.channelAudit.backupsIncomplete"))
                                    }
                                }
                            }
                        }
                        if !flow.rows.isEmpty {
                            Section {
                                ForEach(flow.rows) { row in
                                    NavigationLink { NativeChannelAuditDetail(row: row) } label: {
                                        NativeChannelAuditRow(action: row.action, actor: row.actorID, date: row.createdAt, reason: nil)
                                    }
                                }
                            }
                        }
                    }
                    if flow.state == .ready,
                       (flow.source == .lifecycle ? flow.operations.isEmpty : flow.rows.isEmpty) {
                        ContentUnavailableView { Label("d7.channelAudit.empty", systemImage: "doc.text.magnifyingglass") }
                    }
                    if flow.state == .loading { ProgressView().frame(maxWidth: .infinity) }
                    if flow.state == .unavailable {
                        ContentUnavailableView {
                            Label("d7.channelAudit.loadFailed", systemImage: "exclamationmark.triangle")
                        } actions: {
                            Button("d7.channelAudit.tryAgain") { Task { await flow.refresh() } }
                        }
                    }
                    if flow.canLoadMore { Button("d7.channelAudit.loadMore") { Task { await flow.more() } } }
                }
                .refreshable { await flow.refresh() }
            } else if unavailable {
                ContentUnavailableView {
                    Label("d7.channelAudit.unavailable", systemImage: "lock.shield")
                } actions: {
                    Button("d7.channelAudit.tryAgain") { Task { await open() } }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(flow?.source == .lifecycle ? LocalizedStringKey("d7.channelAudit.historyTitle") : LocalizedStringKey("d7.channelAudit.title"))
        .task { await open() }
        .task {
            while !Task.isCancelled {
                if let flow, !flow.isCurrent { close(); unavailable = true }
                do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            }
        }
        .onDisappear { close() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await open() } } else { close() }
        }
        .privacySensitive()
    }
    private func close() { generation += 1; flow?.deactivate(); flow = nil }
    private func open() async {
        close(); unavailable = false; let run = generation
        do {
            let context = try await channels.currentChannelContext(channelID: channelID)
            guard run == generation, scenePhase == .active, !Task.isCancelled,
                  channels.contextIsCurrent(context), context.serverPermissionNames.contains("VIEW_AUDIT"),
                  let owner = makeFlow(context) else { if run == generation { unavailable = true }; return }
            await owner.activate()
            guard run == generation, scenePhase == .active, !Task.isCancelled else { owner.deactivate(); return }
            flow = owner; unavailable = !owner.isCurrent
        } catch { if run == generation { unavailable = true } }
    }
}

/// One log entry: what happened, who did it, and when.
private struct NativeChannelAuditRow: View {
    let action: String
    let actor: String?
    let date: String
    let reason: String?
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s1) {
            Text(verbatim: action).font(Theme.Font.sectionTitle).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline) {
                if let actor { Text("d7.channelAudit.byMember \(actor)") } else { Text(verbatim: "—") }
                Spacer(minLength: Theme.Space.s2)
                Text(verbatim: date)
            }
            .font(.subheadline).foregroundStyle(.secondary)
            if let reason, !reason.isEmpty { Text(reason).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.vertical, Theme.Space.s1)
        .accessibilityElement(children: .combine)
    }
}

/// Full entry: action, people, date, reason and the recorded changes.
private struct NativeChannelAuditDetail: View {
    let row: NativeChannelAuditFlow.Row
    var body: some View {
        List {
            Section {
                LabeledContent("d7.channelAudit.action") { Text(verbatim: row.action) }
                LabeledContent("d7.channelAudit.by") {
                    if let actor = row.actorID { Text("d7.channelAudit.byMember \(actor)") } else { Text(verbatim: "—") }
                }
                LabeledContent("d7.channelAudit.date") { Text(verbatim: row.createdAt) }
                if let reason = row.reason, !reason.isEmpty {
                    LabeledContent("d7.channelAudit.reason") { Text(reason).multilineTextAlignment(.trailing) }
                }
            }
            Section("d7.channelAudit.changes") {
                if let changes = row.changes {
                    Text(changes).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                } else { Text(verbatim: "—") }
                if row.redacted { Text("d7.channelAudit.redacted").foregroundStyle(.secondary) }
            }
        }
        .nativeChannelFlowPage()
        .navigationTitle(Text(verbatim: row.action))
        .privacySensitive()
    }
}
