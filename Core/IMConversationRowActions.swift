import Foundation

/// The two existing mini-program conversation-row actions. No delete, bulk action,
/// new endpoint or implicit mark-read on appearance is introduced here.
public enum IMConversationRowAction: Equatable {
    case markRead
    case setMuted(Bool)

    public static func available(for conversation: MessagingConversation) -> [Self] {
        var actions: [Self] = []
        if let unread = conversation.unread, unread > 0 { actions.append(.markRead) }
        // An absent/future muted value is unknown, not an inferred false value.
        if let muted = conversation.muted { actions.append(.setMuted(!muted)) }
        return actions
    }
    public var titleKey: String {
        switch self {
        case .markRead: return "im.full.read"
        case .setMuted(let muted): return muted ? "im.full.mute" : "im.full.unmute"
        }
    }
    public var symbolName: String {
        switch self {
        case .markRead: return "envelope.open"
        case .setMuted(let muted): return muted ? "bell.slash" : "bell"
        }
    }
    public func mutation(conversationID: Int) -> IMMutation {
        switch self {
        case .markRead: return .read(conversationID: conversationID)
        case .setMuted(let muted): return .mute(conversationID: conversationID, muted: muted)
        }
    }
    public init?(mutation: IMMutation, conversationID: Int) {
        switch mutation {
        case .read(let id) where id == conversationID: self = .markRead
        case .mute(let id, let muted) where id == conversationID: self = .setMuted(muted)
        default: return nil
        }
    }
    public func matches(_ receipt: IMMutationReceipt) -> Bool {
        switch (self, receipt) {
        case (.markRead, .read): return true
        case (.setMuted(let expected), .muted(let actual)): return expected == actual
        default: return false
        }
    }
}

/// A narrow UI adapter over the existing session-retained coordinator. It never
/// replaces an unknown intent, creates a writer, or fabricates a conversation row.
@MainActor public final class IMConversationRowActions {
    public let conversation: MessagingConversation
    public let identity: MessagingReadIdentity
    public let coordinator: IMExpandedCoordinator
    private let reader: any MessagingReading
    public private(set) var action: IMConversationRowAction?

    public init(conversation: MessagingConversation, identity: MessagingReadIdentity,
                coordinator: IMExpandedCoordinator, reader: any MessagingReading) {
        self.conversation = conversation; self.identity = identity
        self.coordinator = coordinator; self.reader = reader
    }
    public var isCurrent: Bool {
        reader.isConfigured && reader.identity == identity && coordinator.isCurrent
            && coordinator.scope.identity == identity && coordinator.scope.conversationID == conversation.id
    }
    public var state: IMReviewState { isCurrent ? coordinator.visibleState : .idle }
    public var hasMatchingAcknowledgment: Bool {
        guard isCurrent, let action, case .acknowledged(let receipt) = state else { return false }
        return action.matches(receipt)
    }
    public var canPrepare: Bool {
        guard isCurrent, coordinator.writer.isConfigured else { return false }
        switch state {
        case .reviewing(let mutation), .submitting(let mutation), .outcomeUnknown(let mutation):
            return IMConversationRowAction(mutation: mutation, conversationID: conversation.id) != nil
        case .closed: return false
        default: return true
        }
    }
    @discardableResult public func prepare(_ requested: IMConversationRowAction) -> Bool {
        guard canPrepare else { return false }
        switch state {
        case .submitting(let mutation), .outcomeUnknown(let mutation):
            // Reopening a row presents the original pending action, even when the
            // user swiped a different button. A pending send cannot enter this flow.
            action = IMConversationRowAction(mutation: mutation, conversationID: conversation.id)
            return action != nil
        default:
            guard IMConversationRowAction.available(for: conversation).contains(requested),
                  coordinator.review(requested.mutation(conversationID: conversation.id)) else { return false }
            action = requested
            return true
        }
    }
    /// true means an exact current-scope receipt was accepted. The host must still
    /// reread /conversations before showing new unread/muted values.
    public func confirm() async -> Bool {
        guard isCurrent, let action, case .reviewing(let mutation) = state,
              mutation == action.mutation(conversationID: conversation.id) else { return false }
        await coordinator.confirm()
        return acceptedReceipt(for: action)
    }
    public func retryUnchanged() async -> Bool {
        guard isCurrent, let action, case .outcomeUnknown(let mutation) = state,
              mutation == action.mutation(conversationID: conversation.id) else { return false }
        await coordinator.retryUnchanged()
        return acceptedReceipt(for: action)
    }
    public func cancelReview() {
        guard let action, case .reviewing(let mutation) = state,
              mutation == action.mutation(conversationID: conversation.id) else { return }
        coordinator.cancelReview()
    }
    private func acceptedReceipt(for action: IMConversationRowAction) -> Bool {
        guard !Task.isCancelled, isCurrent, case .acknowledged(let receipt) = state else { return false }
        return action.matches(receipt)
    }
}
