import Foundation

public enum DoorReferralFailure: Error, Equatable {
    case disabled, invalid, stale, busy, unknown, alreadyAttempted
    case rejected(String)
}

public struct DoorReferralSession: Equatable {
    public let accountID: Int?
    public let epoch: UUID
    public let token: String?
    public let restored: Bool
    public init(accountID: Int?, epoch: UUID, token: String?, restored: Bool) {
        self.accountID = accountID; self.epoch = epoch; self.token = token; self.restored = restored
    }
}

public enum DoorDestination: Equatable {
    case home
    case activityPlay(activityID: Int, topicID: Int)
    case topicSelfPlay(topicID: Int)
    case topicDetail(topicID: Int)
}

public struct DoorIntent: Equatable {
    public let scene: String?
    public let inviter: String?
    public init(scene: String?, inviter: String?) { self.scene = scene; self.inviter = inviter }
}

public enum DoorParsing {
    /// Exactly one decoding pass. Invalid escape sequences remain raw and fail hex validation.
    public static func scene(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count == 32, value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return value.lowercased()
    }
    public static func inviter(_ raw: String?) -> Int? {
        guard let raw, let value = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else { return nil }
        return value
    }
}

/// Empty origin allowlist by default. Host must inject separately verified HTTPS origins.
/// Route matrix intentionally supports only /door with scene/inviter/id, not arbitrary app routes.
public struct DoorLinkPolicy {
    private let origins: Set<String>
    public init(verifiedHTTPSOrigins: Set<String> = []) {
        self.origins = Set(verifiedHTTPSOrigins.compactMap { raw in
            guard let c = URLComponents(string: raw), c.scheme == "https", let host = c.host,
                  c.user == nil, c.password == nil, c.port == nil, c.query == nil, c.fragment == nil,
                  c.path.isEmpty || c.path == "/" else { return nil }
            return "https://" + host.lowercased()
        })
    }
    public func parse(_ url: URL) -> DoorIntent? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "https",
              let host = c.host, origins.contains("https://" + host.lowercased()),
              c.user == nil, c.password == nil, c.port == nil, c.fragment == nil,
              c.percentEncodedPath == "/door" else { return nil }
        // Parse raw values ourselves to avoid URLQueryItem decoding + scene decoding twice.
        var query: [String: String] = [:]
        for part in (c.percentEncodedQuery ?? "").split(separator: "&", omittingEmptySubsequences: false) {
            if part.isEmpty { continue }
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(pair[0])
            guard ["scene", "inviter", "id"].contains(key), query[key] == nil else { return nil }
            query[key] = pair.count > 1 ? String(pair[1]) : ""
        }
        let referral = query["inviter"] ?? query["id"]
        return DoorIntent(scene: query["scene"], inviter: referral?.removingPercentEncoding ?? referral)
    }
}

public struct DoorScanResult: Decodable, Equatable {
    public let action: String
    public let topicID: Int?
    public let activityID: Int?
    public let nodeID: Int?
    enum CodingKeys: String, CodingKey { case action, topicID = "topicId", activityID = "activityId", nodeID = "nodeId" }
    public init(action: String, topicID: Int?, activityID: Int? = nil, nodeID: Int? = nil) {
        self.action = action; self.topicID = topicID; self.activityID = activityID; self.nodeID = nodeID
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = (try? c.decode(String.self, forKey: .action))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        func id(_ key: CodingKeys) -> Int? {
            if let n = try? c.decode(Int.self, forKey: key) { return n > 0 ? n : nil }
            if let s = try? c.decode(String.self, forKey: key), let n = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)), n > 0 { return n }
            return nil
        }
        topicID = id(.topicID); activityID = id(.activityID); nodeID = id(.nodeID)
    }
    public var destination: DoorDestination? {
        guard let topicID, topicID > 0 else { return nil }
        if action == "play" {
            if let activityID, activityID > 0 { return .activityPlay(activityID: activityID, topicID: topicID) }
            return .topicSelfPlay(topicID: topicID)
        }
        return .topicDetail(topicID: topicID)
    }
}
