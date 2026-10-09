import SwiftUI

@MainActor final class ShopNPCQuestionReuseModel: ObservableObject {
    @Published private(set) var pending: ShopNPCQuestionReuse?
    private let coordinator: ShopNPCCoordinator
    init(coordinator: ShopNPCCoordinator) { self.coordinator = coordinator }
    func select(messageID: UUID, draft: String, enabled: Bool) -> String? {
        pending = nil
        guard enabled, let value = coordinator.prepareQuestionReuse(messageID: messageID, currentDraft: draft) else { return nil }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return coordinator.confirmQuestionReuse(value, currentDraft: draft) }
        if draft.utf8.elementsEqual(value.question.utf8) { return nil }
        pending = value; return nil
    }
    func confirm(id: UUID, draft: String, enabled: Bool) -> String? {
        guard let value = pending, value.id == id else { return nil }
        pending = nil
        guard enabled else { return nil }
        return coordinator.confirmQuestionReuse(value, currentDraft: draft)
    }
    func cancel() { pending = nil }
}

@MainActor struct ShopNPCQuestionReuseButton: View {
    let coordinator: ShopNPCCoordinator
    let messageID: UUID
    @Binding var draft: String
    let enabled: Bool
    @StateObject private var model: ShopNPCQuestionReuseModel
    @State private var showReplacement = false
    init(coordinator: ShopNPCCoordinator, messageID: UUID, draft: Binding<String>, enabled: Bool) {
        self.coordinator = coordinator; self.messageID = messageID; _draft = draft; self.enabled = enabled
        _model = StateObject(wrappedValue: .init(coordinator: coordinator))
    }
    var body: some View {
        Button("shopNPCQuestionReuse.edit") {
            if let text = model.select(messageID: messageID, draft: draft, enabled: enabled) { draft = text }
            else { showReplacement = model.pending != nil }
        }
        .buttonStyle(.bordered).frame(minHeight: 44)
        .disabled(!enabled || !coordinator.canReuseQuestion(messageID: messageID))
        .accessibilityHint("shopNPCQuestionReuse.localOnly")
        .accessibilityIdentifier("shopNPCQuestionReuse.edit." + messageID.uuidString)
        .confirmationDialog("shopNPCQuestionReuse.replaceTitle", isPresented: $showReplacement, titleVisibility: .visible, presenting: model.pending) { receipt in
            Button("shopNPCQuestionReuse.replace") {
                if let text = model.confirm(id: receipt.id, draft: draft, enabled: enabled) { draft = text }
                showReplacement = false
            }
            Button("action.cancel", role: .cancel) { cancel() }
        } message: { _ in Text("shopNPCQuestionReuse.replaceMessage") }
        .onChange(of: showReplacement) { _, showing in if !showing { model.cancel() } }
        .onChange(of: draft) { _, _ in cancel() }
        .onChange(of: enabled) { _, _ in cancel() }
        .onChange(of: coordinator.scope) { _, _ in cancel() }
        .onChange(of: coordinator.active) { _, _ in cancel() }
        .onChange(of: coordinator.isSuspended) { _, _ in cancel() }
        .onDisappear { cancel() }
    }
    private func cancel() { showReplacement = false; model.cancel() }
}
