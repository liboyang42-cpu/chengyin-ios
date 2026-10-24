import Foundation

/// A read-only weekly snapshot. No ranking movement is inferred from these values.
public struct ProfileWeeklyPoints: Decodable, Equatable {
    public let weekPoints: Int
    public let rankPercentage: String
    public let totalUsers: Int
    public let userRank: Int
    private enum CodingKeys: String, CodingKey { case weekPoints, rankPercentage, totalUsers, userRank }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        weekPoints = try values.decode(Int.self, forKey: .weekPoints)
        rankPercentage = try values.decode(String.self, forKey: .rankPercentage)
        totalUsers = try values.decode(Int.self, forKey: .totalUsers)
        userRank = try values.decode(Int.self, forKey: .userRank)
        guard weekPoints >= 0, totalUsers >= 0, userRank >= 0, userRank <= totalUsers,
              !rankPercentage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              rankPercentage.utf8.count <= 128 else { throw APIError.malformedResponse }
    }
}

/// An in-memory identity fence; credentials are neither displayed nor persisted.
public struct ProfileWeeklyPointsSession: Equatable {
    public let identity: ProfileReadIdentity
    private let role: String
    let token: String
    public init(accountID: Int, epoch: UInt64, viewerRevision: UInt64, role: String,
                token: String, approvalRevision: UUID?) throws {
        guard accountID > 0, ["player", "club", "merchant"].contains(role),
              AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch, viewerRevision: viewerRevision,
                         approvalRevision: approvalRevision)
        self.role = role; self.token = token
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity == rhs.identity && lhs.role.utf8.elementsEqual(rhs.role.utf8) &&
            lhs.token.utf8.elementsEqual(rhs.token.utf8)
    }
}

@MainActor public protocol ProfileWeeklyPointsReading: AnyObject {
    var identity: ProfileReadIdentity? { get }
    var isConfigured: Bool { get }
    func weeklyPoints() async throws -> ProfileWeeklyPoints
}

@MainActor public final class ProfileWeeklyPointsSessionReader: ProfileWeeklyPointsReading {
    private let service: ProfileWeeklyPointsService?
    private let currentSession: () -> ProfileWeeklyPointsSession?
    private let onUnauthorized: (ProfileWeeklyPointsSession) -> Void
    public var identity: ProfileReadIdentity? { currentSession()?.identity }
    public var isConfigured: Bool { service != nil && identity?.approvalRevision != nil }
    public init(service: ProfileWeeklyPointsService?, currentSession: @escaping () -> ProfileWeeklyPointsSession?,
                onUnauthorized: @escaping (ProfileWeeklyPointsSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
    }
    public func weeklyPoints() async throws -> ProfileWeeklyPoints {
        try Task.checkCancellation()
        guard let captured = currentSession() else { throw APIError.unauthorized }
        guard captured.identity.approvalRevision != nil, let service else { throw APIError.notConfigured }
        do {
            let value = try await service.read(token: captured.token)
            try Task.checkCancellation()
            guard currentSession() == captured else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentSession() == captured else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(captured) }
            throw error
        }
    }
}
