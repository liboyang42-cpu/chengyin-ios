import Foundation

/// Construct from the live verified account. Advance epoch on every logout/expiration/
/// relogin, even for the same account. Never persist or log this credential-bearing value.
public struct ParticipantWriteSession: Equatable {
    public let identity: ProfileReadIdentity
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = ProfileReadIdentity(accountID: accountID, epoch: epoch); self.token = token
    }
}

@MainActor
public protocol ParticipantWriting: AnyObject {
    var isConfigured: Bool { get }
    var identity: ProfileReadIdentity? { get }
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws
}

/// Credentials never enter the form or coordinator. A pre-dispatch identity mismatch sends
/// nothing. After dispatch, account/token replacement leaves an unknown outcome and never
/// signs out the replacement account or exposes the old response to it.
@MainActor
public final class ParticipantSessionWriter: ParticipantWriting {
    private let service: ParticipantService?
    private let currentSession: () -> ParticipantWriteSession?
    private let onUnauthorized: (ParticipantWriteSession) -> Void
    public var isConfigured: Bool { service != nil }
    public var identity: ProfileReadIdentity? { currentSession()?.identity }

    public init(service: ParticipantService?, currentSession: @escaping () -> ParticipantWriteSession?,
                onUnauthorized: @escaping (ParticipantWriteSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }

    public func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws {
        guard let service else { throw ParticipantWriteError.notSent(.notConfigured) }
        guard let snapshot = currentSession() else { throw ParticipantWriteError.notSent(.unauthorized) }
        guard snapshot.identity == expectedIdentity else { throw ParticipantWriteError.notSent(.unauthorized) }
        guard !Task.isCancelled else { throw ParticipantWriteError.cancelledBeforeDispatch }
        do {
            try await service.perform(mutation, token: snapshot.token)
            guard currentSession() == snapshot else { throw ParticipantWriteError.outcomeUnknown(.accountChanged) }
            guard !Task.isCancelled else { throw ParticipantWriteError.outcomeUnknown(.cancelled) }
        } catch {
            guard currentSession() == snapshot else { throw ParticipantWriteError.outcomeUnknown(.accountChanged) }
            if let writeError = error as? ParticipantWriteError,
               case .rejected(let failure) = writeError, failure.isUnauthorized {
                onUnauthorized(snapshot)
            }
            throw error
        }
    }
}
