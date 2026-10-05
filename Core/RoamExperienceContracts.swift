import Foundation

/// Source: lib/data/api/roam_api.dart. Unknown recovery states are errors, never NOT_FOUND.
public enum RoamRecoveredState: String, Codable { case active = "ACTIVE", finished = "FINISHED", notFound = "NOT_FOUND" }
public struct RoamSettlement: Decodable, Equatable {
    public let tileXp: Int?
    public let poiXp: Int?
    public let totalXp: Int?
    public let newTiles: Int?
    public let newPois: Int?
    public let tilesEver: Int?
    public let medal: String?
    public let sessionShops: Int?
    public let shopMedal: RoamShopBadge?
    enum CodingKeys: String, CodingKey { case tileXp, poiXp, totalXp, newTiles, newPois, tilesEver, medal, sessionShops, shopMedal }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tileXp = try c.decodeIfPresent(Int.self, forKey: .tileXp)
        poiXp = try c.decodeIfPresent(Int.self, forKey: .poiXp)
        totalXp = try c.decodeIfPresent(Int.self, forKey: .totalXp)
        newTiles = try c.decodeIfPresent(Int.self, forKey: .newTiles)
        newPois = try c.decodeIfPresent(Int.self, forKey: .newPois)
        tilesEver = try c.decodeIfPresent(Int.self, forKey: .tilesEver)
        sessionShops = try c.decodeIfPresent(Int.self, forKey: .sessionShops)
        medal = try c.roamText(.medal)
        shopMedal = try c.decodeIfPresent(RoamShopBadge.self, forKey: .shopMedal)
    }
    public var hasRequiredFacts: Bool {
        [tileXp, poiXp, totalXp, newTiles, newPois, tilesEver, sessionShops].allSatisfy { $0 != nil }
    }
}
public struct RoamShopBadge: Decodable, Equatable {
    public let code: String
    public let name: String
    public let statement: String?
    public let iconUrl: String?
    public let threshold: Int?
}
public struct RoamSessionFact: Decodable, Equatable {
    public let state: RoamRecoveredState
    public let sessionID: Int?
    public let clientSessionKey: String?
    public let result: RoamSettlement?
    public let resultComplete: Bool
    public var hasCompleteSettlement: Bool {
        state == .finished && resultComplete && result?.hasRequiredFacts == true
    }
    enum CodingKeys: String, CodingKey { case state, sessionId, clientSessionKey, result, resultComplete }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(RoamRecoveredState.self, forKey: .state)
        sessionID = c.roamInteger(.sessionId)
        clientSessionKey = try c.roamText(.clientSessionKey)
        resultComplete = (try? c.decode(Bool.self, forKey: .resultComplete)) == true
        result = state == .finished ? try c.decodeIfPresent(RoamSettlement.self, forKey: .result) : nil
        if state != .notFound, (sessionID ?? 0) <= 0 { throw APIError.malformedResponse }
        if let result {
            for value in [result.tileXp, result.poiXp, result.totalXp, result.newTiles, result.newPois, result.tilesEver, result.sessionShops] {
                if let value, value < 0 { throw APIError.malformedResponse }
            }
        }
    }
}
public enum RoamRecoveryQuery: Equatable {
    case sessionID(Int), clientSessionKey(String)
    var fields: [String: String] {
        switch self {
        case .sessionID(let id): return ["sessionId": String(id)]
        case .clientSessionKey(let key): return ["clientSessionKey": key]
        }
    }
    func validate() throws {
        switch self {
        case .sessionID(let id): guard id > 0 else { throw APIError.invalidRequest }
        case .clientSessionKey(let key):
            guard !key.isEmpty, key.count <= 256, key == key.trimmingCharacters(in: .whitespacesAndNewlines),
                  !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw APIError.invalidRequest }
        }
    }
    func matches(_ fact: RoamSessionFact) -> Bool {
        if fact.state == .notFound { return true }
        switch self {
        case .sessionID(let id): return fact.sessionID == id
        case .clientSessionKey(let key): return fact.clientSessionKey == key
        }
    }
}
public struct RoamAlbumStamp: Decodable, Equatable, Identifiable {
    public let id: Int
    public let picUrl: String
    public let caption: String?
    public let checkState: Int
    public let createTime: String?
    /// 0 means not submitted to automated review, not rejected. Unknown moderation states are retained
    /// in the contract but withheld from display until their meaning is reviewed.
    public var isVisible: Bool { id > 0 && (checkState == 0 || checkState == 1) }
    enum CodingKeys: String, CodingKey { case id, picUrl, caption, checkState, createTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        picUrl = try c.decodeIfPresent(String.self, forKey: .picUrl) ?? ""
        caption = try c.decodeIfPresent(String.self, forKey: .caption)
        checkState = try c.decodeIfPresent(Int.self, forKey: .checkState) ?? 0
        createTime = try c.decodeIfPresent(String.self, forKey: .createTime)
    }
}
public struct RoamAlbumPage: Decodable, Equatable {
    public let list: [RoamAlbumStamp]
    public let total: Int
    public let pageNum: Int
    public let pageSize: Int
    public var hasMore: Bool { pageNum < (total / pageSize + (total % pageSize == 0 ? 0 : 1)) }
    enum CodingKeys: String, CodingKey { case list, total, pageNum, pageSize }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        list = try c.decodeIfPresent(RoamRows<RoamAlbumStamp>.self, forKey: .list)?.values ?? []
        total = try c.decode(Int.self, forKey: .total)
        pageNum = try c.decode(Int.self, forKey: .pageNum)
        pageSize = try c.decode(Int.self, forKey: .pageSize)
        guard total >= 0, pageNum > 0, (1...100).contains(pageSize), list.count <= pageSize else { throw APIError.malformedResponse }
    }
}
public struct RoamTileMemoryPage: Decodable, Equatable {
    public let tiles: [String]
    public let nextAfterId: Int
    public let hasMore: Bool
    enum CodingKeys: String, CodingKey { case tiles, nextAfterId, hasMore }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tiles = try c.decodeIfPresent([String].self, forKey: .tiles) ?? []
        nextAfterId = try c.decode(Int.self, forKey: .nextAfterId)
        hasMore = try c.decode(Bool.self, forKey: .hasMore)
        guard nextAfterId >= 0, tiles.count <= 2000, tiles.allSatisfy(RoamExperienceMath.isValidTile) else { throw APIError.malformedResponse }
    }
}
/// Voucher DTO parity only. There is deliberately no issue/redeem transport in this batch.
public struct RoamVoucherSnapshot: Decodable, Equatable {
    public let code: String
    public let qrcodeUrl: String
    public let ttlMs: Int
    public var hasCode: Bool { !code.isEmpty }
    // Matches the retained implementation, including its <= 0 fallback (the Dart comment disagrees).
    public var countdownSeconds: Int { (ttlMs > 0 ? ttlMs : 300_000) / 1000 }
    enum CodingKeys: String, CodingKey { case code, qrcodeUrl, ttlMs }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        qrcodeUrl = try c.decodeIfPresent(String.self, forKey: .qrcodeUrl) ?? ""
        ttlMs = try c.decodeIfPresent(Int.self, forKey: .ttlMs) ?? 0
    }
}
public enum RoamVoucherPhase: Equatable { case missing, unavailable, ready, expired }
public struct RoamVoucherClock {
    private let expiresAt: Date
    public init(snapshot: RoamVoucherSnapshot, receivedAt: Date) {
        expiresAt = receivedAt.addingTimeInterval(TimeInterval(snapshot.countdownSeconds))
    }
    public func remaining(at now: Date) -> Int { max(0, Int(ceil(expiresAt.timeIntervalSince(now)))) }
}
public enum RoamExperienceFailure: Error, Equatable {
    case capabilityUnavailable, historyUnreadable, historyWriteFailed, scopeMismatch, incompleteSettlement
}
/// Unreviewed effects cannot be enabled by server fields, remote config or an offline launch flag.
public enum RoamExperienceCapabilities {
    public static let location = false
    public static let presence = false
    public static let settlement = false
    public static let mediaUpload = false
    public static let stampExchange = false
    public static let voucherIssue = false
    public static let redemption = false
    public static let legacyHangout = false
}
