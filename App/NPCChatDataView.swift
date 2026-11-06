import SwiftUI

@MainActor final class NPCChatDataViewModel: ObservableObject {
    let coordinator: NPCChatDataCoordinator
    @Published private(set) var revision = 0
    @Published private(set) var loadIntent: UUID?
    /// Set only by the destructive dialog's confirm button; lifecycle exits clear it.
    @Published private(set) var deletionIntent: UUID?
    private var visible = false
    private var active = false
    init(coordinator: NPCChatDataCoordinator) {
        self.coordinator = coordinator
        coordinator.onChange = { [weak self] in self?.revision += 1 }
    }
    func appear(active: Bool) {
        visible = true; self.active = active
        coordinator.appear(active: active); requestLoad()
    }
    func requestLoad() {
        guard visible, active, coordinator.canLoad else { return }
        loadIntent = UUID()
    }
    func load(_ intent: UUID?) async {
        guard !Task.isCancelled, visible, active, let intent, intent == loadIntent else { return }
        await coordinator.load()
    }
    func requestDeletion() { guard visible, active else { return }; coordinator.requestDeletion() }
    func cancelDeletion() { guard deletionIntent == nil else { return }; coordinator.cancelDeletion() }
    func confirmDeletion() {
        guard visible, active, deletionIntent == nil, coordinator.deletion == .confirming else { return }
        deletionIntent = UUID()
    }
    func runDeletion(_ intent: UUID?) async {
        guard !Task.isCancelled, visible, active, let intent, intent == deletionIntent else { return }
        await coordinator.confirmDeletion()
        if deletionIntent == intent { deletionIntent = nil }
    }
    func suspend() { active = false; loadIntent = nil; deletionIntent = nil; coordinator.suspend() }
    func foreground() { guard visible else { return }; active = true; coordinator.foreground() }
    func sessionChanged() { loadIntent = nil; deletionIntent = nil; coordinator.sessionChanged() }
    func disappear() { visible = false; active = false; loadIntent = nil; deletionIntent = nil; coordinator.invalidate() }
    var deletionFailureKey: LocalizedStringKey? {
        guard case .failed(let failure) = coordinator.deletion else { return nil }
        return LocalizedStringKey("npcLogDelete.failure." + failure.rawValue)
    }
}

struct NPCChatDataPresentation: Identifiable {
    let id = UUID()
    let coordinator: NPCChatDataCoordinator
}

/// Owns the navigation container so opening a row does not retire the list's
/// private memory; dismissing this sheet or backgrounding does retire it.
@MainActor struct NPCChatDataView: View {
    @StateObject private var model: NPCChatDataViewModel
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(coordinator: NPCChatDataCoordinator) { _model = StateObject(wrappedValue: .init(coordinator: coordinator)) }
    private var coordinator: NPCChatDataCoordinator { model.coordinator }
    private var filtered: [NPCChatDataRecord] {
        Array((coordinator.data?.records ?? []).reversed()).filter { $0.matches(query) }
    }
    var body: some View {
        NavigationStack {
            List {
                Section { Text("npcData.boundary").font(.footnote).foregroundStyle(.secondary) }
                if coordinator.phase == .loading { ProgressView("npcData.loading") }
                if let value = coordinator.data {
                    Section("npcData.policy") {
                        if let days = value.retentionDays {
                            LabeledContent("npcData.retentionDays") { Text(verbatim: String(days)) }
                        }
                        if let policy = value.retentionPolicy, !policy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(verbatim: policy).textSelection(.enabled)
                        } else { Text("npcData.policyNotReturned").foregroundStyle(.secondary) }
                        LabeledContent("npcData.recordCount") { Text(verbatim: String(value.records.count)) }
                    }.accessibilityIdentifier("npcData.policy")
                    Section("npcData.records") {
                        if value.records.isEmpty { Text("npcData.empty").accessibilityIdentifier("npcData.empty") }
                        else if filtered.isEmpty { Text("npcData.noMatches") }
                        ForEach(filtered) { record in
                            NavigationLink { [recordID = record.id] in
                                NPCChatDataRecordView(model: model, recordID: recordID)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let question = record.userMessage, !question.isEmpty { Text(verbatim: question).lineLimit(2) }
                                    else { Text("npcData.noQuestion") }
                                    if let time = record.sourceTime { Text(verbatim: time).font(.caption).foregroundStyle(.secondary) }
                                }
                            }.accessibilityIdentifier("npcData.record." + record.id)
                        }
                    }
                }
                if let failure = coordinator.failure {
                    Section { Text(LocalizedStringKey(failure.messageKey)).accessibilityIdentifier("npcData.failure") }
                }
                if coordinator.canRequestDeletion || coordinator.deletion != .idle {
                    NPCChatLogDeletionSection(model: model)
                }
                if coordinator.canLoad {
                    Section {
                        Button("npcData.reload") { query = ""; model.requestLoad() }
                            .accessibilityIdentifier("npcData.reload")
                    }
                }
            }
            .searchable(text: $query, prompt: "npcData.search")
            .navigationTitle("npcData.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.done") { model.disappear(); query = ""; dismiss() } } }
            .confirmationDialog(Text("npcLogDelete.confirmTitle", tableName: "NPCChatLogDeletion"), isPresented: Binding(
                get: { coordinator.deletion == .confirming && model.deletionIntent == nil },
                set: { if !$0 { model.cancelDeletion() } }
            ), titleVisibility: .visible) {
                Button(role: .destructive) { model.confirmDeletion() } label: { Text("npcLogDelete.confirm", tableName: "NPCChatLogDeletion") }
                    .accessibilityIdentifier("npcLogDelete.confirm")
                Button(role: .cancel) { model.cancelDeletion() } label: { Text("npcLogDelete.cancel", tableName: "NPCChatLogDeletion") }
            } message: { Text("npcLogDelete.confirmMessage", tableName: "NPCChatLogDeletion") }
        }
        .privacySensitive()
        .accessibilityIdentifier("npcData.screen")
        .onAppear { model.appear(active: scenePhase == .active) }
        .task(id: model.loadIntent) { [intent = model.loadIntent] in await model.load(intent) }
        .task(id: model.deletionIntent) { [intent = model.deletionIntent] in await model.runDeletion(intent) }
        .onChange(of: coordinator.currentSession) { _, _ in query = ""; model.sessionChanged() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.foreground() }
            else { query = ""; model.suspend() }
        }
        .onDisappear { query = ""; model.disappear() }
    }
}

/// Log deletion only (BK-EXISTING); shown only when a host injected an approved deleter.
@MainActor private struct NPCChatLogDeletionSection: View {
    @ObservedObject var model: NPCChatDataViewModel
    var body: some View {
        let coordinator = model.coordinator
        Section {
            Text("npcLogDelete.scope", tableName: "NPCChatLogDeletion").font(.footnote).foregroundStyle(.secondary)
            switch coordinator.deletion {
            case .deleting:
                ProgressView { Text("npcLogDelete.deleting", tableName: "NPCChatLogDeletion") }
            case .deleted(let count):
                LabeledContent { Text(verbatim: String(count)) } label: { Text("npcLogDelete.deletedCount", tableName: "NPCChatLogDeletion") }
                    .accessibilityIdentifier("npcLogDelete.deleted")
                Text("npcLogDelete.deletedBoundary", tableName: "NPCChatLogDeletion").font(.footnote)
            case .unknown:
                Text("npcLogDelete.unknown", tableName: "NPCChatLogDeletion").accessibilityIdentifier("npcLogDelete.unknown")
            case .failed:
                if let key = model.deletionFailureKey {
                    Text(key, tableName: "NPCChatLogDeletion").accessibilityIdentifier("npcLogDelete.failure")
                }
            case .idle, .confirming:
                EmptyView()
            }
            if coordinator.canRequestDeletion {
                Button(role: .destructive) { model.requestDeletion() } label: { Text("npcLogDelete.action", tableName: "NPCChatLogDeletion") }
                    .accessibilityIdentifier("npcLogDelete.action")
            }
        } header: { Text("npcLogDelete.title", tableName: "NPCChatLogDeletion") }
    }
}

@MainActor private struct NPCChatDataRecordView: View {
    @ObservedObject var model: NPCChatDataViewModel
    let recordID: String
    /// Look up by ID on every render. Never capture a private record in navigation
    /// state where it could survive the parent's account/epoch invalidation.
    private var record: NPCChatDataRecord? { model.coordinator.data?.records.first(where: { $0.id == recordID }) }
    var body: some View {
        Form {
            if let record {
                Section("npcData.question") {
                    if let text = record.userMessage, !text.isEmpty { Text(verbatim: text).textSelection(.enabled) }
                    else { Text("npcData.noQuestion") }
                }
                Section("npcData.reply") {
                    if let text = record.npcReply, !text.isEmpty { Text(verbatim: text).textSelection(.enabled) }
                    else { Text("npcData.noReply") }
                }
                Section("npcData.sourceTime") {
                    if let time = record.sourceTime { Text(verbatim: time) }
                    else { Text("npcData.timeNotReturned") }
                    Text("npcData.timeBoundary").font(.footnote).foregroundStyle(.secondary)
                }
                Section { Text("npcData.historicalBoundary").font(.footnote).foregroundStyle(.secondary) }
            } else { Text("npcData.contentCleared").accessibilityIdentifier("npcData.contentCleared") }
        }
        .navigationTitle("npcData.recordTitle").navigationBarTitleDisplayMode(.inline)
        .privacySensitive()
    }
}
