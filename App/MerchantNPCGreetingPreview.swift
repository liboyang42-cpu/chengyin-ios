import SwiftUI

/// An ephemeral, read-only projection of two already-authorized draft fields.
/// Its snapshot never copies persona/knowledge or creates a chat, save or publication action.
@MainActor final class MerchantNPCGreetingPreviewModel: Identifiable {
    struct Snapshot: Equatable {
        let name: String
        let greeting: String
    }
    let id = UUID()
    private weak var document: MerchantOperationsViewModel?
    private let scope: UUID
    private let draftIdentity: UUID
    private let revision: Int
    private var stored: Snapshot?
    static let maximumUTF8Bytes = 4_096

    init?(document: MerchantOperationsViewModel) {
        guard let snapshot = Self.read(document) else { return nil }
        self.document = document; stored = snapshot; scope = document.coordinator.reader.scope
        draftIdentity = document.coordinator.draftIdentity; revision = document.revision
    }
    static func canOpen(_ document: MerchantOperationsViewModel) -> Bool { read(document) != nil }
    private static func read(_ document: MerchantOperationsViewModel) -> Snapshot? {
        let owner = document.coordinator
        guard owner.destination == .character, owner.isCurrent, !owner.isBusy, !owner.isLocked, owner.confirmation == nil,
              case .character(let draft) = owner.draft,
              draft.name.utf8.count <= maximumUTF8Bytes,
              draft.greeting.utf8.count <= maximumUTF8Bytes - draft.name.utf8.count else { return nil }
        return .init(name: draft.name, greeting: draft.greeting)
    }
    var snapshot: Snapshot? {
        guard let stored else { return nil }
        guard let document, document.coordinator.reader.scope == scope, document.coordinator.draftIdentity == draftIdentity,
              document.revision == revision, let current = Self.read(document),
              current.name.utf8.elementsEqual(stored.name.utf8), current.greeting.utf8.elementsEqual(stored.greeting.utf8) else {
            self.stored = nil; return nil
        }
        return stored
    }
    func retire() { stored = nil }
}

@MainActor struct MerchantNPCGreetingPreviewEntry: View {
    @ObservedObject var document: MerchantOperationsViewModel
    @State private var preview: MerchantNPCGreetingPreviewModel?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Section {
            Button("merchantGreetingPreview.open", systemImage: "text.bubble") {
                guard scenePhase == .active else { return }
                preview = .init(document: document)
            }.disabled(!MerchantNPCGreetingPreviewModel.canOpen(document))
                .frame(minHeight: 44).accessibilityIdentifier("merchantGreetingPreview.open")
            Text("merchantGreetingPreview.boundary").font(.footnote).foregroundStyle(.secondary)
            if !MerchantNPCGreetingPreviewModel.canOpen(document) {
                Text("merchantGreetingPreview.unavailable").font(.footnote)
            }
        }
        .sheet(item: $preview, onDismiss: close) { model in MerchantNPCGreetingPreviewSheet(model: model, document: document) }
        .onChange(of: document.revision) { _, _ in if preview?.snapshot == nil { close() } }
        .onChange(of: document.coordinator.reader.scope) { _, _ in close() }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in close() }
        .onChange(of: document.coordinator.isCurrent) { _, current in if !current { close() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { close() } }
        .onDisappear { close() }
    }
    private func close() { preview?.retire(); preview = nil }
}

@MainActor struct MerchantNPCGreetingPreviewSheet: View {
    let model: MerchantNPCGreetingPreviewModel
    @ObservedObject private var document: MerchantOperationsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(model: MerchantNPCGreetingPreviewModel, document: MerchantOperationsViewModel) { self.model = model; self.document = document }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("merchantGreetingPreview.boundary").font(.footnote)
                        .accessibilityIdentifier("merchantGreetingPreview.boundary")
                    if let snapshot = model.snapshot {
                        Label("merchantGreetingPreview.handwritten", systemImage: "pencil").font(.caption)
                        ChatMessageBubble(isOwn: false) {
                            if snapshot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text("merchantGreetingPreview.noName") }
                            else { Text(verbatim: snapshot.name) }
                        } content: {
                            if snapshot.greeting.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("merchantGreetingPreview.noGreeting").foregroundStyle(.secondary)
                            } else { Text(verbatim: snapshot.greeting).textSelection(.enabled) }
                        }.accessibilityIdentifier("merchantGreetingPreview.card")
                    } else { Text("merchantGreetingPreview.retired") }
                    Text("merchantGreetingPreview.ephemeral").font(.footnote).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("merchantGreetingPreview.title").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.done") { close() }.frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("merchantGreetingPreview.close")
                }
            }
        }
        .privacySensitive()
        .onChange(of: document.revision) { _, _ in if model.snapshot == nil { close() } }
        .onChange(of: document.coordinator.reader.scope) { _, _ in close() }
        .onChange(of: document.coordinator.draftIdentity) { _, _ in close() }
        .onChange(of: document.coordinator.isCurrent) { _, current in if !current { close() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { close() } }
        .onDisappear { model.retire() }
    }
    private func close() { model.retire(); dismiss() }
}
