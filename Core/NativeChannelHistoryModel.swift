import Foundation

/// One screen lifetime, one operation at a time; no background polling or receipts.
@MainActor public final class NativeChannelHistoryModel {
    public enum Operation: Equatable { case latest, older(Int), newer(Int), read(Int) }
    public let conversation: MessagingConversation
    public let client: NativeChannelSessionClient
    private let capturedIdentity: MessagingReadIdentity?
    public private(set) var history: NativeChannelHistory
    public private(set) var receipt: NativeChannelReadReceipt?
    public private(set) var issue: Error?
    public private(set) var failedOperation: Operation?
    public private(set) var isLoading = false
    public private(set) var loaded = false
    public private(set) var seenThrough: Int?
    private var seenPosition = -1
    private var generation = 0
    private var active = false
    private var activeOperation: Operation?
    public var onChange: (() -> Void)?
    public var isCurrent: Bool { active && client.isConfigured && capturedIdentity != nil && client.identity == capturedIdentity }
    public var visibleMessages: [MessagingMessage] { isCurrent ? history.messages : [] }
    /// A pushed message detail may outlive the history screen's active loading
    /// lifetime, but never its exact account/lease authority or latest snapshot.
    public func detailMessage(_ id: Int) -> MessagingMessage? {
        guard client.isConfigured, capturedIdentity != nil, client.identity == capturedIdentity else { return nil }
        return history.messages.first { $0.id == id }
    }
    public init(conversation: MessagingConversation, client: NativeChannelSessionClient) {
        self.conversation = conversation; self.client = client; capturedIdentity = client.identity
        history = .init(conversationID: conversation.id)
    }
    public func activate() { active = true }
    public func stop() {
        // Cancellation is not proof that the server rolled back an ACK. Preserve
        // its exact cutoff for an explicit retry when this screen returns.
        if let operation = activeOperation, case .read = operation {
            failedOperation = operation; issue = APIError.malformedResponse; receipt = nil
        }
        activeOperation = nil; active = false; generation += 1; isLoading = false; onChange?()
    }
    /// Called by an explicit seen-through action, not by network completion. Compare source positions,
    /// never numeric IDs, and never ACK an unloaded message.
    public func observed(_ messageID: Int) {
        guard isCurrent, let position = history.messages.firstIndex(where: { $0.id == messageID }) else { return }
        if position >= seenPosition { seenPosition = position; seenThrough = messageID; onChange?() }
    }
    public func load() async { await perform(.latest) }
    public func older() async {
        guard history.older.hasMore, let cursor = history.older.nextCursor else { return }
        await perform(.older(cursor))
    }
    public func newer() async {
        guard loaded, client.canLoadNewer else { return }
        await perform(.newer(history.nextAfter))
    }
    public func markSeen() async {
        guard client.canReadThrough, let seenThrough else { return }
        await perform(.read(seenThrough))
    }
    public func retry() async { if let failedOperation { await perform(failedOperation) } }
    private func perform(_ operation: Operation) async {
        guard isCurrent, !isLoading, conversation.kind == .group else { return }
        // An uncertain receipt cannot be replaced by a new cutoff. Retry the same
        // idempotent read intent before any further page/read operation.
        if let failedOperation, case .read = failedOperation, failedOperation != operation { return }
        isLoading = true; activeOperation = operation; issue = nil; generation += 1
        let request = generation
        onChange?()
        defer { if request == generation { activeOperation = nil; isLoading = false; onChange?() } }
        do {
            switch operation {
            case .latest:
                let page = try await client.page(conversationID: conversation.id, cursor: 0)
                guard isCurrent, request == generation, !Task.isCancelled else { return }
                try history.replace(page); loaded = true; seenThrough = nil; seenPosition = -1; receipt = nil
            case .older(let cursor):
                let page = try await client.page(conversationID: conversation.id, cursor: cursor)
                guard isCurrent, request == generation, !Task.isCancelled else { return }
                try history.prepend(page, cursor: cursor)
                if let seenThrough { seenPosition = history.messages.firstIndex { $0.id == seenThrough } ?? -1 }
            case .newer(let after):
                let result = try await client.newer(conversationID: conversation.id, after: after)
                guard isCurrent, request == generation, !Task.isCancelled else { return }
                try history.append(result.page, requestedAfter: after, nextAfter: result.nextAfter)
                if !result.page.messages.isEmpty { receipt = nil }
                if let seenThrough { seenPosition = history.messages.firstIndex { $0.id == seenThrough } ?? -1 }
            case .read(let target):
                guard history.messages.contains(where: { $0.id == target }) else { throw APIError.invalidRequest }
                let result = try await client.readThrough(conversationID: conversation.id, readTo: target)
                guard isCurrent, request == generation, !Task.isCancelled else { return }
                receipt = result
                NativePushAttemptReader.signalOriginalReadCommitted()
            }
            failedOperation = nil
        } catch {
            guard request == generation else { return }
            if !isCurrent {
                // A retired authority must never expose or retry the former viewer's payload.
                history = .init(conversationID: conversation.id); receipt = nil; loaded = false; seenThrough = nil
                failedOperation = nil
            } else if error is CancellationError {
                // Task cancellation alone is not a server rollback. Preserve the
                // exact loaded snapshot and read target while its authority is
                // unchanged, so a new explicit retry can pass the loaded-target guard.
                issue = APIError.malformedResponse; failedOperation = operation
                if case .read = operation { receipt = nil }
            } else {
                issue = error; failedOperation = operation
                if case .read = operation, let failure = error as? MessagingReadFailure,
                   failure.httpStatus == nil, let code = failure.code, [400,401,403,404,409].contains(code) {
                    // A structured rejection from this transactional endpoint is
                    // not an unknown write. Recover with a fresh authorized page.
                    failedOperation = .latest
                }
                if let failure = error as? MessagingReadFailure,
                   failure.isForbidden || failure.isClosed || failure.isUnauthorized || failure.code == 404
                    || failure.errorCode == "IM_CONVERSATION_CLOSED" {
                    history = .init(conversationID: conversation.id); receipt = nil; loaded = false; seenThrough = nil
                }
            }
        }
    }
}
