import Foundation

public enum CityParticipationCommandFailure: Error, Equatable {
    case disabled, invalid, busy, staleSession, storage, unverified
}
/// Exact original six-kind producer. No old CityActionIntent, payer or game-action translation.
public struct CityParticipationCommand: Codable, Equatable {
    public enum Kind: String, Codable { case create = "CREATE", join = "JOIN", lock = "LOCK", confirm = "CONFIRM", exit = "EXIT", resume = "RESUME" }
    public let kind: Kind
    public let requestId: String
    public let regionId: String
    public let releaseId: Int64
    public let contentHash: String
    public let expectedVersion: Int64
    public let teamId: String?
    public let inviteCode: String?
    public init(kind: Kind, requestID: String, regionID: String, releaseID: Int64, contentHash: String,
                expectedVersion: Int64, teamID: String? = nil, inviteCode: String? = nil) throws {
        self.kind = kind; requestId = requestID; regionId = regionID; releaseId = releaseID
        self.contentHash = contentHash; self.expectedVersion = expectedVersion; teamId = teamID; self.inviteCode = inviteCode
        try validate()
    }
    public func validate() throws {
        func uuid(_ value: String?) -> Bool {
            guard let value else { return false }
            return value.range(of: #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z"#, options: .regularExpression) != nil
        }
        guard Self.id(requestId), Self.id(regionId), releaseId > 0, expectedVersion >= 0,
              contentHash.range(of: #"^[a-f0-9]{64}\z"#, options: .regularExpression) != nil,
              (kind == .create ? teamId == nil : uuid(teamId)),
              (kind == .join ? uuid(inviteCode) : inviteCode == nil) else { throw CityParticipationCommandFailure.invalid }
    }
    static func id(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,95}\z"#, options: .regularExpression) != nil
    }
    public func wireBytes() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= 4096 else { throw CityParticipationCommandFailure.invalid }
        return data
    }
}

/// Live credential is ephemeral; durable journal contains only its explicit deployment/account tuple.
public struct CityParticipationCommandScope: Equatable {
    public let session: CityOriginalReceiptSession
    private let credential: String
    public init(market: RegionalMarket, baseURL: URL, namespace: String, accountID: Int, epoch: UInt64, token: String) throws {
        session = try .init(market: market, baseURL: baseURL, namespace: namespace, accountID: accountID, epoch: epoch, token: token)
        credential = token
    }
    var token: String { credential }
    var durableKey: [String] { [session.market.rawValue, session.baseURL.absoluteString, session.namespace, String(session.accountID)] }
}
/// Exact original bytes plus live session. No production issuer is installed; default grant remains nil.
@MainActor public final class CityParticipationCommandGrant {
    public let scope: CityParticipationCommandScope
    public let bytes: Data
    public private(set) var isRevoked = false
    public init(scope: CityParticipationCommandScope, command: CityParticipationCommand) throws {
        self.scope = scope; bytes = try command.wireBytes()
    }
    public func revoke() { isRevoked = true }
}
