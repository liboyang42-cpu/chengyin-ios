import Foundation

public enum IMConversationReadAllPhase: Equatable {
    case reviewing, running, finished, cancelled
}

public enum IMConversationReadAllOutcome: Equatable {
    case notAttempted, submitting, acknowledged, rejected, outcomeUnknown, protectedIntent, unavailable
}

public struct IMConversationReadAllItem: Identifiable, Equatable {
    public let conversation: MessagingConversation
    public fileprivate(set) var outcome: IMConversationReadAllOutcome = .notAttempted
    public var id: Int { conversation.id }
}

/// P032 onReadAll uses the loaded list, across categories, without a bulk API.
/// This native adapter is deliberately conservative about unknown conversation types.
/// The frozen array is finite; one request is in flight at a time. All writes use
/// the existing session-owned coordinator and its original pending-intent journal.
@MainActor public final class IMConversationReadAll {
    public let identity: MessagingReadIdentity
    public private(set) var items: [IMConversationReadAllItem]
    public private(set) var phase: IMConversationReadAllPhase = .reviewing
    public private(set) var stopRequested = false
    public private(set) var attemptedCount = 0
    public var onChange: (() -> Void)?
    private let reader: any MessagingReading
    private let owners: [IMExpandedCoordinator?]

    public static func eligible(_ conversations: [MessagingConversation]) -> [MessagingConversation] {
        var seen = Set<Int>()
        return conversations.filter { conversation in
            guard conversation.id > 0, let unread = conversation.unread, unread > 0,
                  [.direct, .system, .merchant].contains(conversation.kind) else { return false }
            return seen.insert(conversation.id).inserted
        }
    }

    public init(conversations: [MessagingConversation], identity: MessagingReadIdentity,
                reader: any MessagingReading, coordinator: (Int) -> IMExpandedCoordinator?) {
        self.identity = identity; self.reader = reader
        let frozen = Self.eligible(conversations)
        items = frozen.map { IMConversationReadAllItem(conversation: $0) }
        // Capture original owners once. A later session/factory replacement must
        // not silently attach an old confirmation to new authority.
        owners = frozen.map { coordinator($0.id) }
    }
    public var isCurrent: Bool { reader.isConfigured && reader.identity == identity }
    public var canConfirm: Bool {
        phase == .reviewing && !stopRequested && isCurrent && items.indices.contains { index in
            guard let owner = owners[index] else { return false }
            return matches(owner, at: index) && canReview(owner)
        }
    }
    public var acknowledgedCount: Int { count(.acknowledged) }
    public var unknownCount: Int { count(.outcomeUnknown) }
    public var rejectedCount: Int { count(.rejected) }
    public var remainingCount: Int { items.count - acknowledgedCount - unknownCount - rejectedCount }
    private func count(_ outcome: IMConversationReadAllOutcome) -> Int {
        items.filter { $0.outcome == outcome }.count
    }

    /// Cancels only unstarted work. In-flight transport may still finish; its
    /// coordinator keeps the receipt/unknown intent and is never reset on Close.
    public func stop() {
        guard !stopRequested else { return }
        stopRequested = true
        if phase == .reviewing { phase = .cancelled }
        onChange?()
    }
    public func confirm() async {
        guard canConfirm, !Task.isCancelled else { return }
        phase = .running; onChange?()
        // Serial iteration (maximum concurrency = 1), no recursive requests,
        // auto retry, list expansion, or catch-up loop for newly arrived messages.
        for index in items.indices {
            guard !stopRequested, !Task.isCancelled, isCurrent else { break }
            guard let owner = owners[index], matches(owner, at: index) else {
                items[index].outcome = .unavailable; onChange?(); continue
            }
            guard canReview(owner) else {
                items[index].outcome = .protectedIntent; onChange?(); continue
            }
            let mutation = IMMutation.read(conversationID: items[index].id)
            guard owner.review(mutation) else {
                items[index].outcome = .protectedIntent; onChange?(); continue
            }
            // review emits a synchronous owner callback. Revalidate authority and
            // the exact reviewed mutation before invoking the existing dispatcher.
            guard !stopRequested, !Task.isCancelled, isCurrent, matches(owner, at: index),
                  owner.visibleState == .reviewing(mutation) else {
                if owner.visibleState == .reviewing(mutation) { owner.cancelReview() }
                break
            }
            attemptedCount += 1
            items[index].outcome = .submitting
            // Do not emit an adapter callback between this final check and dispatch.
            await owner.confirm()
            if !isCurrent || !matches(owner, at: index) {
                items[index].outcome = .outcomeUnknown
            } else {
                switch owner.visibleState {
                case .acknowledged(.read): items[index].outcome = .acknowledged
                case .rejected, .closed: items[index].outcome = .rejected
                default: items[index].outcome = .outcomeUnknown
                }
            }
            onChange?()
            await Task.yield()
        }
        phase = .finished; onChange?()
        // The App adapter invalidates the real list owner once after all attempted
        // work settles, including partial/unknown outcomes. Only its server read
        // may replace badges. This class never edits a MessagingConversation.
    }
    private func matches(_ owner: IMExpandedCoordinator, at index: Int) -> Bool {
        isCurrent && owner.isCurrent && owner.writer.isConfigured
            && owner.scope.identity == identity && owner.scope.conversationID == items[index].id
    }
    private func canReview(_ owner: IMExpandedCoordinator) -> Bool {
        switch owner.visibleState {
        case .idle, .acknowledged, .rejected: return true
        // Protect all pending intents, including another read, mute or message.
        case .reviewing, .submitting, .outcomeUnknown, .closed: return false
        }
    }
}
