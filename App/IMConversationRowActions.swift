import SwiftUI

struct IMConversationRowButtonToken: Equatable {
    enum Operation: Equatable { case confirm, retryUnchanged }
    let id: UUID
    let appearance: UUID
    let operation: Operation
    let mutation: IMMutation
}

@MainActor final class IMConversationRowReviewModel: ObservableObject {
    @Published private(set) var state: IMReviewState
    @Published private(set) var appearance: UUID?
    @Published private(set) var isActionPending = false
    let actions: IMConversationRowActions
    private var queued: IMConversationRowButtonToken?
    private var executing: IMConversationRowButtonToken?
    private let invalidateList: () -> Void
    init(actions: IMConversationRowActions, invalidateList: @escaping () -> Void = {}) {
        self.actions = actions; self.invalidateList = invalidateList; state = actions.state
    }
    func observe() {
        let lifetime = UUID()
        appearance = lifetime; queued = nil; executing = nil; isActionPending = false
        actions.coordinator.onChange = { [weak self] in
            guard let self, self.appearance == lifetime else { return }
            self.state = self.actions.state
        }
        state = actions.state
    }
    /// Called synchronously by a button in this exact rendered appearance. Tasks
    /// may consume this token once; they cannot create or restore an appearance.
    func prepare(_ operation: IMConversationRowButtonToken.Operation,
                 appearance expected: UUID?) -> IMConversationRowButtonToken? {
        guard let expected, appearance == expected, actions.isCurrent,
              queued == nil, executing == nil else { return nil }
        let mutation: IMMutation
        switch (operation, actions.state) {
        case (.confirm, .reviewing(let value)), (.retryUnchanged, .outcomeUnknown(let value)): mutation = value
        default: return nil
        }
        guard let action = actions.action,
              mutation == action.mutation(conversationID: actions.conversation.id) else { return nil }
        let token = IMConversationRowButtonToken(id: UUID(), appearance: expected,
            operation: operation, mutation: mutation)
        queued = token; isActionPending = true
        return token
    }
    func perform(_ token: IMConversationRowButtonToken) async -> Bool {
        guard queued == token, appearance == token.appearance else { return false }
        queued = nil
        guard actions.isCurrent, !Task.isCancelled, matchesPendingMutation(token) else {
            isActionPending = false; state = actions.state; return false
        }
        executing = token
        let accepted: Bool
        switch token.operation {
        case .confirm: accepted = await actions.confirm()
        case .retryUnchanged: accepted = await actions.retryUnchanged()
        }
        // Receipt ownership and UI ownership are separate. A confirmed operation
        // still invalidates its exact list cache after Close, without reviving UI.
        let matchingReceipt = accepted && actions.isCurrent && actions.hasMatchingAcknowledgment
            && actions.action?.mutation(conversationID: actions.conversation.id) == token.mutation
        if matchingReceipt { invalidateList() }
        // An old completion cannot overwrite or notify a newly opened sheet.
        guard appearance == token.appearance, executing == token else { return false }
        executing = nil; isActionPending = false
        guard actions.isCurrent else { state = .idle; return false }
        state = actions.state
        return matchingReceipt && !Task.isCancelled
    }
    private func matchesPendingMutation(_ token: IMConversationRowButtonToken) -> Bool {
        switch (token.operation, actions.state) {
        case (.confirm, .reviewing(let mutation)), (.retryUnchanged, .outcomeUnknown(let mutation)):
            return mutation == token.mutation
                && actions.action?.mutation(conversationID: actions.conversation.id) == token.mutation
        default: return false
        }
    }
    func dismiss() {
        // Invalidate before cancelReview emits a synchronous owner callback.
        appearance = nil; queued = nil; executing = nil; isActionPending = false
        actions.cancelReview(); state = .idle
        // The session owner's outcomeUnknown/submitting journal remains intact.
    }
}

/// Sheet presentation is owned by the list, outside its loading/error subtree.
/// Receipt acknowledgment requests a list read; it never updates badges locally.
@MainActor struct IMConversationRowActionsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: IMConversationRowReviewModel
    init(actions: IMConversationRowActions, invalidateList: @escaping () -> Void) {
        _model = StateObject(wrappedValue: IMConversationRowReviewModel(actions: actions,
            invalidateList: invalidateList))
    }
    var body: some View {
        let appearance = model.appearance
        NavigationStack {
            Form {
                if model.actions.isCurrent {
                    Section("im.row.conversation") {
                        MessagingConversationName(conversation: model.actions.conversation)
                        if let action = model.actions.action {
                            Label(LocalizedStringKey(action.titleKey), systemImage: action.symbolName)
                        }
                    }
                    Section {
                        switch model.state {
                        case .reviewing:
                            Text("im.row.reviewHint")
                            Button("im.full.confirm") {
                                guard let token = model.prepare(.confirm, appearance: appearance) else { return }
                                Task { _ = await model.perform(token) }
                            }
                            .disabled(model.isActionPending)
                            .accessibilityIdentifier("im.row.confirm")
                        case .submitting:
                            ProgressView("im.full.submitting").accessibilityIdentifier("im.row.submitting")
                        case .outcomeUnknown:
                            Text("im.row.unknown")
                            Button("im.full.retrySame") {
                                guard let token = model.prepare(.retryUnchanged, appearance: appearance) else { return }
                                Task { _ = await model.perform(token) }
                            }
                            .disabled(model.isActionPending)
                            .accessibilityIdentifier("im.row.retrySame")
                        case .acknowledged:
                            if model.actions.hasMatchingAcknowledgment {
                                Text("im.row.acknowledged")
                                    .accessibilityIdentifier("im.row.acknowledged")
                            } else { Text("im.row.receiptMismatch") }
                        case .rejected:
                            Text("im.full.rejected")
                        case .closed:
                            Text("im.full.closed")
                        case .idle:
                            Text("im.full.disabled")
                        }
                    }
                } else { Text("messaging.signInHint") }
            }
            .navigationTitle(Text("im.row.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { model.dismiss(); dismiss() }.accessibilityIdentifier("im.row.close")
                }
            }
        }
        .privacySensitive()
        .accessibilityIdentifier("im.row.review")
        .onAppear { model.observe() }
        .onDisappear { model.dismiss() }
    }
}

@MainActor struct IMConversationRowActionPresentation: Identifiable {
    let id = UUID()
    let actions: IMConversationRowActions
}
