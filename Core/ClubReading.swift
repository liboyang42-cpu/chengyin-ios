import Foundation

/// Epoch changes on logout, expiration, credential replacement and same-account relogin.
public struct ClubReadIdentity: Hashable {
    public let accountID: Int?
    public let epoch: UInt64
    public init(accountID: Int?, epoch: UInt64) { self.accountID = accountID; self.epoch = epoch }
    public var isSignedIn: Bool { accountID != nil }
}

/// Never persist or log credentials. Guest snapshots also carry an epoch.
public struct ClubReadSession: Equatable {
    public let identity: ClubReadIdentity
    fileprivate let token: String?
    public init(guestEpoch: UInt64) {
        identity = ClubReadIdentity(accountID: nil, epoch: guestEpoch); token = nil
    }
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = ClubReadIdentity(accountID: accountID, epoch: epoch); self.token = token
    }
}

/// UI adapters additionally conform to ObservableObject and publish identity changes.
@MainActor
public protocol ClubReading: AnyObject {
    var isClubConfigured: Bool { get }
    var clubIdentity: ClubReadIdentity { get }
    var clubDiscoveryScope: ClubDiscoveryScope { get }
    func clubMerchantLocality() async throws -> MerchantClubLocality
    func clubHome() async throws -> ClubHome
    func clubOwned() async throws -> [ClubRecord]
    func clubDirectory(name: String?) async throws -> [ClubRecord]
    func clubDetail(id: Int) async throws -> ClubRecord
    func clubDetail(id: Int, isCurrent: @escaping () -> Bool) async throws -> ClubRecord
    func clubMembers(id: Int) async throws -> ClubMemberDirectory
    func clubMembers(id: Int, isCurrent: @escaping () -> Bool) async throws -> ClubMemberDirectory
}

extension ClubReading {
    public func clubDetail(id: Int, isCurrent: @escaping () -> Bool) async throws -> ClubRecord {
        guard isCurrent() else { throw CancellationError() }
        let value = try await clubDetail(id: id)
        guard !Task.isCancelled, isCurrent() else { throw CancellationError() }
        return value
    }
    public func clubMembers(id: Int, isCurrent: @escaping () -> Bool) async throws -> ClubMemberDirectory {
        guard isCurrent() else { throw CancellationError() }
        let value = try await clubMembers(id: id)
        guard !Task.isCancelled, isCurrent() else { throw CancellationError() }
        return value
    }
}

/// Existing player/guest readers keep their original unfiltered home and make no locality request.
public extension ClubReading {
    var clubDiscoveryScope: ClubDiscoveryScope { .init(identity: clubIdentity) }
    func clubMerchantLocality() async throws -> MerchantClubLocality { throw APIError.notConfigured }
}

/// Capture the live session before every operation, including both member-list reads.
/// Reject old successes and failures even when the underlying transport ignores cancellation.
@MainActor
public final class ClubSessionReader: ClubReading {
    private let service: ClubService?
    private let currentSession: () -> ClubReadSession
    private let onUnauthorized: (ClubReadSession) -> Void
    public var isClubConfigured: Bool { service != nil }
    public var clubIdentity: ClubReadIdentity { currentSession().identity }
    public init(service: ClubService?, currentSession: @escaping () -> ClubReadSession,
                onUnauthorized: @escaping (ClubReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func clubHome() async throws -> ClubHome {
        try await read { service, session in try await service.home(token: session.token) }
    }
    public func clubOwned() async throws -> [ClubRecord] {
        try await read { service, session in
            guard let token = session.token else { throw ClubReadFailure.unauthorized(message: nil) }
            return try await service.owned(token: token)
        }
    }
    public func clubDirectory(name: String?) async throws -> [ClubRecord] {
        try await read { service, session in try await service.directory(name: name, token: session.token) }
    }
    public func clubDetail(id: Int) async throws -> ClubRecord {
        try await read { service, session in try await service.detail(id: id, token: session.token) }
    }
    public func clubDetail(id: Int, isCurrent: @escaping () -> Bool) async throws -> ClubRecord {
        try await read(isCurrent: isCurrent) { service, session in try await service.detail(id: id, token: session.token) }
    }
    public func clubMembers(id: Int) async throws -> ClubMemberDirectory {
        try await clubMembers(id: id, isCurrent: { true })
    }
    public func clubMembers(id: Int, isCurrent: @escaping () -> Bool) async throws -> ClubMemberDirectory {
        try await read(isCurrent: isCurrent) { service, session in
            guard let token = session.token else { throw ClubReadFailure.unauthorized(message: nil) }
            let club = try await service.detail(id: id, token: token)
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            guard self.currentSession() == session else { throw CancellationError() }
            let members = try await service.members(in: club, token: token)
            return ClubMemberDirectory(club: club, members: members)
        }
    }
    private func read<Value>(isCurrent: () -> Bool = { true }, _ operation: (ClubService, ClubReadSession) async throws -> Value) async throws -> Value {
        guard isCurrent() else { throw CancellationError() }
        guard let service else { throw APIError.notConfigured }
        let snapshot = currentSession()
        try Task.checkCancellation()
        do {
            let result = try await operation(service, snapshot)
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            guard currentSession() == snapshot else { throw CancellationError() }
            return result
        } catch {
            guard isCurrent() else { throw CancellationError() }
            guard !Task.isCancelled, currentSession() == snapshot else { throw CancellationError() }
            if (error as? ClubReadFailure)?.isUnauthorized == true, snapshot.identity.isSignedIn {
                onUnauthorized(snapshot)
            }
            throw error
        }
    }
}
