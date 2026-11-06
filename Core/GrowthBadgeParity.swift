import Foundation

/// Mini-program growth center parity: a badge is "newly lit" only relative to the
/// previous successful center read in the same scope. The first read never celebrates.
public struct GrowthBadgeUnlockTracker: Equatable {
    private var previous: [String]?
    public init() {}
    /// Stable comparison code: badge code, else display name (the source's `badgeCode || name`).
    public static func code(_ badge: GrowthCenterBadge) -> String? {
        GrowthCenterFormatting.nonempty(badge.code) ?? GrowthCenterFormatting.nonempty(badge.name)
    }
    public mutating func observe(_ badges: [GrowthCenterBadge]) -> [GrowthCenterBadge] {
        let codes = badges.compactMap(Self.code)
        defer { previous = codes }
        guard let previous else { return [] }
        return badges.filter { badge in Self.code(badge).map { !previous.contains($0) } ?? false }
    }
    public mutating func reset() { previous = nil }
}

/// Podium split of a successfully decoded board. Rows keep server order; nothing is re-ranked.
public struct GrowthLeaderboardPodium: Equatable {
    public let first: GrowthLeaderboardEntry?
    public let second: GrowthLeaderboardEntry?
    public let third: GrowthLeaderboardEntry?
    public let rest: [GrowthLeaderboardEntry]
    /// Only a ranked viewer row is highlighted; an unranked `me` stays out of the list.
    public let me: GrowthLeaderboardEntry?
    public init(board: GrowthLeaderboard) {
        let list = board.list
        first = list.first
        second = list.count > 1 ? list[1] : nil
        third = list.count > 2 ? list[2] : nil
        rest = Array(list.dropFirst(3))
        me = board.me.rank == nil ? nil : board.me
    }
    public var isEmpty: Bool { first == nil && me == nil }
}

/// Deterministic fallback avatar monogram/glyph from player nickname (`"匿"` when blank)
/// so leaderboard rows have a clean native avatar representation without loading remote media.
public struct GrowthLeaderboardAvatarBadge: Equatable, Sendable {
    public let monogram: String
    public let paletteIndex: Int

    public init(nickname: String?, memberID: Int? = nil) {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let first = trimmed.first {
            self.monogram = String(first).uppercased()
        } else {
            self.monogram = "匿"
        }
        let seed = memberID ?? trimmed.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        self.paletteIndex = abs(seed) % 6
    }

    public init(entry: GrowthLeaderboardEntry) {
        self.init(nickname: entry.nickname, memberID: entry.memberID)
    }
}

/// Badge wall caption: "已点亮 X / N · 还有 Y 枚等待探索". Counts only rows actually received;
/// a failed medal read (nil) is not counted as zero medals.
public struct ObjectBadgeWallSummary: Equatable {
    public let unlocked: Int
    public let total: Int
    public var locked: Int { total - unlocked }
    public init(wall: ProfileBadgeWall) {
        let medals = wall.medals ?? []
        total = wall.identities.count + medals.count
        unlocked = wall.identities.filter(\.unlocked).count + medals.count
    }
}

/// Authoritative readback for a play-side "view collection" jump carrying a badge code.
/// The wall reads are independent of the completion response, so only a found row is claimed.
public enum ObjectBadgeWallFocus: Equatable {
    case unlocked(name: String)
    case locked(name: String)
    case notOnWall
    public static func resolve(code: String?, wall: ProfileBadgeWall) -> ObjectBadgeWallFocus? {
        guard let code = GrowthCenterFormatting.nonempty(code) else { return nil }
        if let identity = wall.identities.first(where: { $0.badgeCode == code }) {
            return identity.unlocked ? .unlocked(name: identity.badgeName) : .locked(name: identity.badgeName)
        }
        if let medal = (wall.medals ?? []).first(where: { !$0.badgeCode.isEmpty && $0.badgeCode == code }) {
            return .unlocked(name: medal.medalName)
        }
        return .notOnWall
    }
}

/// Object-card and stamp-album read access variants from the mini-program (`readAccess`).
public enum CollectionReadAccess: Equatable {
    case login, denied
    public init?(_ error: Error) {
        switch error {
        case APIError.unauthorized: self = .login
        case APIError.httpStatus(403), APIError.businessCode(403): self = .denied
        default: return nil
        }
    }
}

/// Object-card pile/grid toggle (`onGather` parity: `✦ 收拢` / `✦ 散开`).
public enum ObjectCardPileMode: String, Equatable, Sendable {
    case scatteredPile
    case gatheredGrid

    public var buttonLabel: String {
        switch self {
        case .scatteredPile: return "✦ 收拢"
        case .gatheredGrid: return "✦ 散开"
        }
    }

    public mutating func toggle() {
        self = (self == .scatteredPile) ? .gatheredGrid : .scatteredPile
    }

    public func toggled() -> ObjectCardPileMode {
        self == .scatteredPile ? .gatheredGrid : .scatteredPile
    }
}

/// Deterministic stamp-album collage slot (`layout.js` rotation & offset parity + page-size constants).
public struct StampAlbumCollageSlot: Equatable, Sendable {
    public static let sourcePageSize: Int = 50
    public static let fixturePageSize: Int = 20
    private static let rotationTable: [Double] = [-4, 2.5, -2, 3.5, -3, 1.5, 4, -1.5, 2, -3.5]
    private static let offsetXTable: [Double] = [-6, 4, -3, 6, -5, 3, 5, -4, 2, -2]
    private static let offsetYTable: [Double] = [2, -3, 4, -2, 3, -4, 1, 3, -2, 4]

    public let index: Int
    public let rotationDegrees: Double
    public let offsetX: Double
    public let offsetY: Double

    public init(index: Int) {
        let normalized = max(0, index)
        let slot = normalized % Self.rotationTable.count
        self.index = normalized
        self.rotationDegrees = Self.rotationTable[slot]
        self.offsetX = Self.offsetXTable[slot]
        self.offsetY = Self.offsetYTable[slot]
    }
}
