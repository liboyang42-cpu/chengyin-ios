import Foundation

/// The viewer's own place on `api/growth/leaderboard`. The source fills an unranked `me` with
/// score 0 and "TOP100%" (no rank row, or no ranked members yet); neither is evidence, so only a
/// ranked row keeps its score and bucket. Outside the returned Top N keeps the real rank/score.
public enum GrowthLeaderboardStanding: Equatable {
    case listed(rank: Int, score: Int?)
    case outsideList(rank: Int, score: Int?)
    case unknown
    public init(board: GrowthLeaderboard) {
        guard let rank = board.me.rank, rank > 0 else { self = .unknown; return }
        self = rank <= board.list.count ? .listed(rank: rank, score: board.me.score) : .outsideList(rank: rank, score: board.me.score)
    }
    public var rank: Int? {
        switch self { case .listed(let rank, _), .outsideList(let rank, _): return rank; case .unknown: return nil }
    }
    public var score: Int? {
        switch self { case .listed(_, let score), .outsideList(_, let score): return score; case .unknown: return nil }
    }
}

public extension GrowthLeaderboard {
    var standing: GrowthLeaderboardStanding { .init(board: self) }
}

extension GrowthLeaderboard {
    /// Drops the source's placeholder score/bucket from an unranked viewer row. Rank stays as sent.
    func withoutUnrankedPlaceholders() -> GrowthLeaderboard {
        guard me.rank.map({ $0 <= 0 }) ?? true else { return self }
        return GrowthLeaderboard(metric: metric, period: period, list: list,
            me: GrowthLeaderboardEntry(rank: me.rank, memberID: me.memberID, nickname: me.nickname, avatar: me.avatar, score: nil, rankPercentage: nil))
    }
}

extension GrowthLeaderboardEntry {
    init(rank: Int?, memberID: Int?, nickname: String?, avatar: String?, score: Int?, rankPercentage: String?) {
        self.rank = rank; self.memberID = memberID; self.nickname = nickname; self.avatar = avatar
        self.score = score; self.rankPercentage = rankPercentage
    }
}
