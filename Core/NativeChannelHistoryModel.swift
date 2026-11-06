import Foundation

/// One screen lifetime, one operation at a time; no background polling or receipts.
@MainActor public final class NativeChannelHistoryModel {
    public enum Operation: Equatable { case latest, older(Int), newer(Int), read(Int) }
    /// Capture a visible action before scheduling a Task. This is a local veto,
    /// never a transport, membership or receipt capability.
    public enum Action { case load, older, newer, markSeen, retry }
    public struct PreparedAction {
        fileprivate let owner: UUID
        fileprivate let generation: Int
        fileprivate let operation: Operation
    }
    private let actionOwner = UUID()
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
    public func prepare(_ action: Action) -> PreparedAction? {
        guard isCurrent, !isLoading, conversation.kind == .group else { return nil }
        let operation: Operation
        switch action {
        case .load: operation = .latest
        case .older:
            guard history.older.hasMore, let cursor = history.older.nextCursor else { return nil }
            operation = .older(cursor)
        case .newer:
            guard loaded, client.canLoadNewer else { return nil }
            operation = .newer(history.nextAfter)
        case .markSeen:
            guard client.canReadThrough, let seenThrough else { return nil }
            operation = .read(seenThrough)
        case .retry:
            guard let failedOperation else { return nil }
            operation = failedOperation
        }
        return PreparedAction(owner: actionOwner, generation: generation, operation: operation)
    }
    public func perform(_ action: PreparedAction) async {
        // stop(), replacement reads and another admitted action retire this tap.
        // Freeze retry/cursor/read targets at preparation, not when this Task runs.
        guard !Task.isCancelled, isCurrent, action.owner == actionOwner,
              action.generation == generation else { return }
        await perform(action.operation)
    }
    private func perform(_ operation: Operation) async {
        guard isCurrent, !isLoading, conversation.kind == .group else { return }
        // An uncertain receipt cannot be replaced by a new cutoff. Retry the same
        // idempotent read intent before any further page/read operation.
        if let failedOperation, case .read = failedOperation, failedOperation != operation { return }
        isLoading = true; activeOperation = operation; issue = nil; generation += 1
        // A previous cutoff's receipt cannot describe this in-flight intent.
        if case .read = operation { receipt = nil }
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
                history = .init(conversationID: conversation.id); receipt = nil; loaded = false; seenThrough = nil; seenPosition = -1
                failedOperation = nil
            } else if error is CancellationError {
                // Task cancellation alone is not a server rollback. Preserve the
                // exact loaded snapshot and read target while its authority is
                // unchanged, so a new explicit retry can pass the loaded-target guard.
                issue = APIError.malformedResponse; failedOperation = operation
                if case .read = operation { receipt = nil }
            } else {
                issue = error; failedOperation = operation
                let failure = error as? MessagingReadFailure
                // HTTP status takes precedence over envelope metadata: an HTTP
                // 5xx with a rejection code still leaves the write uncertain.
                let rejection = failure.map { failure in
                    [400,401,403,404,409].contains(failure.httpStatus ?? failure.code ?? 0)
                } ?? false
                if case .read = operation, rejection {
                    // A structured rejection from this transactional endpoint is
                    // not an unknown write. Recover with a fresh authorized page.
                    failedOperation = .latest
                }
                let accessRejected = failure.map { failure in
                    (failure.httpStatus == nil || rejection) &&
                    (failure.isForbidden || failure.isClosed || failure.isUnauthorized || failure.code == 404
                     || failure.httpStatus == 404 || failure.errorCode == "IM_CONVERSATION_CLOSED")
                } ?? false
                // MessagingSessionReader deliberately maps structured 401s to
                // APIError.unauthorized, even before its session owner retires.
                if (error as? APIError) == .unauthorized || accessRejected {
                    history = .init(conversationID: conversation.id); receipt = nil; loaded = false; seenThrough = nil; seenPosition = -1
                    // The old page/read target no longer exists locally. A
                    // subsequent explicit retry must reacquire the latest page.
                    failedOperation = .latest
                }
            }
        }
    }
}
