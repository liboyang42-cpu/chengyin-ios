import Foundation

/// An entry-specific projection of the existing account reader. No request implementation
/// or another account surface's configuration/authorization is replaced.
@MainActor public final class ProfileInviteHistoryReader: SocialAccountReading {
    private let base: any SocialAccountReading
    private let currentAccess: () -> ProfileInviteHistoryReadAccess?
    private struct Snapshot: Equatable {
        let identity: SocialAccountIdentity
        let baseRevision: UInt64
        let configured: Bool
        let accessRevision: UUID?
    }
    private var observed: Snapshot?
    private var revision: UInt64 = 0
    public init(base: any SocialAccountReading, currentAccess: @escaping () -> ProfileInviteHistoryReadAccess?) {
        self.base = base; self.currentAccess = currentAccess
    }
    public var identity: SocialAccountIdentity { base.identity }
    public var presentationRevision: UInt64 { _ = synchronize(); return revision }
    public var isConfigured: Bool { synchronize().configured }
    public var isOfflineExample: Bool { base.isOfflineExample }
    private func access() -> ProfileInviteHistoryReadAccess? {
        guard let value = currentAccess(), !value.isRevoked,
              value.context.session.accountID == base.identity.accountID,
              value.context.session.epoch == base.identity.epoch,
              value.context.role == base.identity.role else { return nil }
        return value
    }
    private func synchronize() -> Snapshot {
        let approved = access()
        let value = Snapshot(identity: base.identity, baseRevision: base.presentationRevision,
            configured: base.isConfigured && approved != nil, accessRevision: approved?.revision)
        if observed != value { observed = value; revision &+= 1 }
        return value
    }
    public func invitationHistory(page: Int) async throws -> SocialInviteHistory {
        try await read { try await base.invitationHistory(page: page) }
    }
    // Pushed invited-member detail retains the same reader identity. Its original public-info
    // permission remains independent; an invitation approval cannot authorize that request.
    public func publicProfile(memberID: Int) async throws -> SocialPublicProfile {
        try await read { try await base.publicProfile(memberID: memberID) }
    }
    public func informationList() async throws -> [SocialInformation] { throw APIError.notConfigured }
    public func information(id: Int) async throws -> SocialInformation { throw APIError.notConfigured }
    private func read<T>(_ operation: () async throws -> T) async throws -> T {
        guard identity.accountID != nil else { throw APIError.unauthorized }
        let snapshot = synchronize(), capturedRevision = revision
        guard snapshot.configured, let captured = access() else { throw APIError.notConfigured }
        try Task.checkCancellation()
        do {
            let value = try await operation()
            try Task.checkCancellation()
            guard access() === captured, synchronize() == snapshot, revision == capturedRevision else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, access() === captured, synchronize() == snapshot,
                  revision == capturedRevision else { throw CancellationError() }
            throw error
        }
    }
}
