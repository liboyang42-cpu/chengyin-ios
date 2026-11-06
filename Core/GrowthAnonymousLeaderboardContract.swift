import Foundation

/// Selection of an existing source contract, never a network permission.
/// Anonymous wire is documented by the c64ab8d producer candidate; production
/// transport admission remains independently held until that producer is reviewed.
public enum GrowthLeaderboardReadContract {
    case legacy
    case anonymous
}

/// Strict anonymous DTO. An identity-bearing legacy payload is an error, including
/// an explicitly null memberId. Do not silently strip identity after accepting it.
struct GrowthAnonymousLeaderboardSnapshot: Decodable {
    let metric: GrowthBoardMetric
    let period: GrowthBoardPeriod
    let list: [Item]
    let me: Item

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: WireKey.self)
        try Self.whitelist(c, allowed: ["metric", "period", "list", "me"])
        metric = try c.decode(GrowthBoardMetric.self, forKey: .init("metric"))
        period = try c.decode(GrowthBoardPeriod.self, forKey: .init("period"))
        list = try c.decode([Item].self, forKey: .init("list"))
        me = try c.decode(Item.self, forKey: .init("me"))
        guard me.isSelf, me.rank.map({ $0 > 0 }) ?? true, list.count <= 100 else { throw APIError.malformedResponse }
        // Source assigns consecutive positions in its already ordered top list.
        for (index, row) in list.enumerated() {
            guard row.rank == index + 1 else { throw APIError.malformedResponse }
        }
        let selfRows = list.filter(\.isSelf)
        guard selfRows.count <= 1 else { throw APIError.malformedResponse }
        if let rank = me.rank, rank <= list.count {
            guard selfRows.first?.rank == rank else { throw APIError.malformedResponse }
        }
        if let row = selfRows.first {
            guard row.rank == me.rank, row.score == me.score else { throw APIError.malformedResponse }
        }
    }

    func projection(query: GrowthBoardQuery, limit: Int) throws -> GrowthLeaderboard {
        guard metric == query.metric, period == query.period, list.count <= limit else { throw APIError.malformedResponse }
        // The public presentation model has legacy optional identity fields. They
        // are deliberately always absent here, even for the authenticated self row.
        return GrowthLeaderboard(metric: metric, period: period,
            list: try list.map { try $0.projection() }, me: try me.projection()).withoutUnrankedPlaceholders()
    }

    struct Item: Decodable {
        let rank: Int?
        let score: Int64?
        let isSelf: Bool
        let rankPercentage: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: WireKey.self)
            try GrowthAnonymousLeaderboardSnapshot.whitelist(c,
                allowed: ["rank", "score", "nickname", "avatar", "rankPercentage", "self"])
            let rawRank = try c.decodeIfPresent(Int32.self, forKey: .init("rank"))
            rank = rawRank.map(Int.init)
            score = try c.decodeIfPresent(Int64.self, forKey: .init("score"))
            isSelf = try c.decode(Bool.self, forKey: .init("self"))
            rankPercentage = try c.decodeIfPresent(String.self, forKey: .init("rankPercentage"))
            let nickname = try c.decodeIfPresent(String.self, forKey: .init("nickname"))
            let avatar = try c.decodeIfPresent(String.self, forKey: .init("avatar"))
            // Producer promises this exact anonymous projection for other players.
            guard isSelf || (nickname == "匿名玩家" && avatar == nil) else { throw APIError.malformedResponse }
        }
        func projection() throws -> GrowthLeaderboardEntry {
            let integer: Int?
            if let score {
                guard let exact = Int(exactly: score) else { throw APIError.malformedResponse }
                integer = exact
            } else { integer = nil }
            return GrowthLeaderboardEntry(rank: rank, memberID: nil, nickname: nil, avatar: nil,
                score: integer, rankPercentage: rankPercentage)
        }
    }

    private struct WireKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private static func whitelist(_ c: KeyedDecodingContainer<WireKey>, allowed: Set<String>) throws {
        guard Set(c.allKeys.map(\.stringValue)).isSubset(of: allowed) else { throw APIError.malformedResponse }
    }
}
