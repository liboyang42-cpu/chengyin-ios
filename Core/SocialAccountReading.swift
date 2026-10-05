import Foundation
import Observation

public struct SocialAccountIdentity: Equatable, Hashable {
    public let accountID: Int?
    public let epoch: UInt64
    /// Server-supplied role only; entry intent must not grant authoring privileges.
    public let role: String?
    public init(accountID: Int?, epoch: UInt64, role: String? = nil) { self.accountID = accountID; self.epoch = epoch; self.role = role }
}
public struct SocialAccountSession: Equatable {
    public let identity: SocialAccountIdentity
    fileprivate let token: String?
    public init(guestEpoch: UInt64) { identity = .init(accountID: nil, epoch: guestEpoch); token = nil }
    public init(accountID: Int, epoch: UInt64, role: String?, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch, role: role); self.token = token
    }
}
@MainActor public protocol SocialAccountReading: AnyObject {
    var identity: SocialAccountIdentity { get }
    /// Presentation lifetime only, never an authorization or role grant.
    var presentationRevision: UInt64 { get }
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    func publicProfile(memberID: Int) async throws -> SocialPublicProfile
    func informationList() async throws -> [SocialInformation]
    func information(id: Int) async throws -> SocialInformation
    func invitationHistory(page: Int) async throws -> SocialInviteHistory
}
extension SocialAccountReading {
    public var presentationRevision: UInt64 { 0 }
}
@MainActor @Observable public final class SocialAccountSessionReader: SocialAccountReading {
    private let service: SocialAccountService?
    private let currentSession: () -> SocialAccountSession
    private let onUnauthorized: (SocialAccountSession) -> Void
    public private(set) var presentationRevision: UInt64 = 0
    public var identity: SocialAccountIdentity { _ = presentationRevision; return currentSession().identity }
    /// Called by the existing session owner when account, role, token or epoch changes.
    /// The monotonic revision also retires an unobserved A-to-B-to-A transition.
    public func invalidatePresentation() { presentationRevision &+= 1 }
    public var isConfigured: Bool { service != nil }
    public var isOfflineExample: Bool { false }
    public init(service: SocialAccountService?, currentSession: @escaping () -> SocialAccountSession, onUnauthorized: @escaping (SocialAccountSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func publicProfile(memberID: Int) async throws -> SocialPublicProfile { try await read { try await $0.profile(memberID: memberID, token: $1) } }
    public func informationList() async throws -> [SocialInformation] { try await read { service, token in try await service.informationList(token: token) } }
    public func information(id: Int) async throws -> SocialInformation { try await read { service, token in try await service.information(id: id, token: token) } }
    public func invitationHistory(page: Int) async throws -> SocialInviteHistory {
        guard identity.accountID != nil else { throw APIError.unauthorized }
        return try await read { service, token in
            guard let token else { throw APIError.unauthorized }
            return try await service.invitationHistory(page: page, token: token)
        }
    }
    private func read<T>(_ operation: (SocialAccountService, String?) async throws -> T) async throws -> T {
        guard let service else { throw APIError.notConfigured }
        let snapshot = currentSession(), revision = presentationRevision
        try Task.checkCancellation()
        do {
            let value = try await operation(service, snapshot.token)
            try Task.checkCancellation()
            guard currentSession() == snapshot, presentationRevision == revision else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentSession() == snapshot, presentationRevision == revision else { throw CancellationError() }
            if error as? APIError == .unauthorized, snapshot.token != nil { onUnauthorized(snapshot) }
            throw error
        }
    }
}
