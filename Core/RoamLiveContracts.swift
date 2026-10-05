import Foundation

/// A reviewed, exact-account deployment grant. Never populated from a URL, API response or defaults.
public struct RoamLiveApproval {
    public static let requiredPaths: Set<String> = ["api/roam/reveal", "api/roam/session", "api/roam/finish", "api/roam/pois", "api/roam/poi/discover", "api/roam/shop/visit", "api/map/nearby"]
    public let endpoints: OperationEndpointApproval
    public let foregroundLocation: Bool
    public let presence: Bool
    public init(endpoints: OperationEndpointApproval, foregroundLocation: Bool = false, presence: Bool = false) {
        self.endpoints = endpoints; self.foregroundLocation = foregroundLocation; self.presence = presence
    }
    public func allows(_ identity: RoamExperienceIdentity, api: APIConfiguration) -> Bool {
        identity.scope.market == "cn" && foregroundLocation && endpoints.baseURL == api.baseURL &&
        identity.scope.deployment == api.baseURL.absoluteString && endpoints.namespace == identity.scope.namespace &&
        endpoints.accountID == identity.scope.accountID && Self.requiredPaths.isSubset(of: endpoints.paths)
    }
}
public enum RoamLiveFailure: Error, Equatable {
    case unavailable, consentRequired, foregroundRequired, locationQuality, staleIdentity, recoveryRequired, journalUnavailable, outOfRange, unresolvedVisit, capacityReached
}
public enum RoamLivePhase: Equatable { case ready, acquiring, active, paused, recoveryRequired, recovering, finishing, finished, unavailable, locationDenied }
public enum RoamLivePending: String, Codable { case reveal, finish }

/// Durable write-ahead recovery metadata. Exact GPS fixes, tracks, other people, and tokens stay out.
/// Geohash7 tiles and measured aggregate distance are needed to replay the idempotent reveal and finish.
public struct RoamLiveRecord: Codable, Equatable {
    public let scope: RoamHistoryScope
    public let clientSessionKey: String
    public let startedAt: Date
    public var sessionID: Int?
    public var allTiles: [String] = []
    public var pendingTiles: [String] = []
    public var distanceMeters: Double = 0
    public var confirmedPOIIDs: [Int] = []
    public var confirmedShops: [String] = []
    public var unresolvedActions: [String] = []
    public var finishRequested = false
    public var pendingWrite: RoamLivePending?
    public init(scope: RoamHistoryScope, clientSessionKey: String, startedAt: Date) {
        self.scope = scope; self.clientSessionKey = clientSessionKey; self.startedAt = startedAt
    }
    public func validate() throws {
        guard startedAt.timeIntervalSince1970.isFinite, startedAt.timeIntervalSince1970 > 0,
              startedAt.timeIntervalSince1970 < Double(Int64.max / 1000), clientSessionKey.count == 32, clientSessionKey.allSatisfy({ "0123456789abcdef".contains($0) }),
              (sessionID ?? 1) > 0, distanceMeters.isFinite, (0...Double(Int32.max)).contains(distanceMeters),
              allTiles.count <= 10_000, allTiles.allSatisfy({ $0.count == 7 && RoamExperienceMath.isValidTile($0) }),
              Set(allTiles).count == allTiles.count, Set(pendingTiles).isSubset(of: Set(allTiles)), Set(pendingTiles).count == pendingTiles.count,
              confirmedPOIIDs.count <= 10_000, confirmedPOIIDs.allSatisfy({ $0 > 0 }),
              confirmedShops.count <= 10_000, unresolvedActions.count <= 10_000 else { throw RoamLiveFailure.journalUnavailable }
    }
}
@MainActor public final class RoamLiveJournal {
    private struct Envelope: Codable { let version: Int; let scope: RoamHistoryScope; let record: RoamLiveRecord? }
    private let storage: any RoamHistoryDataStoring
    public init(storage: any RoamHistoryDataStoring) { self.storage = storage }
    private func key(_ scope: RoamHistoryScope) -> String { "roam-live-v1-" + scope.storageKey }
    public func read(scope: RoamHistoryScope) throws -> RoamLiveRecord? {
        do {
            guard let data = try storage.read(key: key(scope)) else { return nil }
            guard data.count <= 1_000_000 else { throw RoamLiveFailure.journalUnavailable }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1, envelope.scope == scope, envelope.record == nil || envelope.record?.scope == scope else { throw RoamLiveFailure.journalUnavailable }
            try envelope.record?.validate(); return envelope.record
        } catch { throw RoamLiveFailure.journalUnavailable }
    }
    public func write(_ record: RoamLiveRecord) throws {
        try record.validate()
        try store(Envelope(version: 1, scope: record.scope, record: record))
    }
    /// Only clear after matching complete settlement has been archived, or before any session/write existed.
    public func clear(scope: RoamHistoryScope) throws { try store(Envelope(version: 1, scope: scope, record: nil)) }
    private func store(_ envelope: Envelope) throws {
        do {
            let data = try JSONEncoder().encode(envelope)
            try storage.write(data, key: key(envelope.scope))
            guard try storage.read(key: key(envelope.scope)) == data else { throw RoamLiveFailure.journalUnavailable }
        } catch { throw RoamLiveFailure.journalUnavailable }
    }
}
public struct RoamLiveRevealReceipt: Decodable {
    public let sessionId: Int
    public let newlyRevealed: Int
    enum CodingKeys: String, CodingKey { case sessionId, newlyRevealed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.roamInteger(.sessionId), id > 0 else { throw APIError.malformedResponse }
        sessionId = id; newlyRevealed = try c.decode(Int.self, forKey: .newlyRevealed)
        guard newlyRevealed >= 0 else { throw APIError.malformedResponse }
    }
}
public struct RoamLiveDiscoveryReceipt: Decodable {
    public let discovered: Bool
    public let poiId: Int
    public let meaning: String?
    // `xp` is a source rule value, not proof that rewards have settled; deliberately not exposed.
}
public struct RoamLiveShopReceipt: Decodable { public let recorded: Bool }
@MainActor public protocol RoamLiveServing: AnyObject {
    var identity: RoamExperienceIdentity? { get }
    var isAvailable: Bool { get }
    var presenceAvailable: Bool { get }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt
    func fact(key: String) async throws -> RoamSessionFact
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace]
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode]
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws
}
