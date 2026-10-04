import Foundation

public struct MessagingReadIdentity: Hashable {
    public let accountID: Int
    public let epoch: UInt64
    public init(accountID: Int, epoch: UInt64) { self.accountID = accountID; self.epoch = epoch }
}

/// Do not persist/log. Construct from the live session; epoch changes on logout/expiry
/// and all login attempts, including relogin to the same account.
public struct MessagingReadSession: Equatable {
    public let identity: MessagingReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = MessagingReadIdentity(accountID: accountID, epoch: epoch)
        self.token = token
    }
}

@MainActor
public protocol MessagingReading: AnyObject {
    var isConfigured: Bool { get }
    var identity: MessagingReadIdentity? { get }
    func messagingConversations() async throws -> [MessagingConversation]
    func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage
}

@MainActor
public final class MessagingSessionReader: MessagingReading {
    private let service: MessagingService?
    private let currentSession: () -> MessagingReadSession?
    private let onUnauthorized: (MessagingReadSession) -> Void
    private let isAvailable: () -> Bool
    public var isConfigured: Bool { service != nil && isAvailable() }
    public var identity: MessagingReadIdentity? { currentSession()?.identity }
    public init(service: MessagingService?, currentSession: @escaping () -> MessagingReadSession?,
                isAvailable: @escaping () -> Bool = { true },
                onUnauthorized: @escaping (MessagingReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.isAvailable = isAvailable; self.onUnauthorized = onUnauthorized
    }
    public func messagingConversations() async throws -> [MessagingConversation] {
        try await read { service, token in try await service.conversations(token: token) }
    }
    public func messagingMessages(conversationID: Int, cursor: Int = 0) async throws -> MessagingPage {
        try await read { service, token in
            try await service.messages(conversationID: conversationID, cursor: cursor, token: token)
        }
    }
    private func read<Value>(_ operation: (MessagingService, String) async throws -> Value) async throws -> Value {
        guard let service, isAvailable() else { throw APIError.notConfigured }
        guard let snapshot = currentSession() else { throw APIError.unauthorized }
        try Task.checkCancellation()
        do {
            let result = try await operation(service, snapshot.token)
            try Task.checkCancellation()
            guard isAvailable(), currentSession() == snapshot else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, isAvailable(), currentSession() == snapshot else { throw CancellationError() }
            if let failure = error as? MessagingReadFailure, failure.isUnauthorized {
                onUnauthorized(snapshot)
                throw APIError.unauthorized
            }
            throw error
        }
    }
}
