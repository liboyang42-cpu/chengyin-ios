import Foundation

/// Mini-program pages/roam/index 漫游护照 tab (`_loadIntroPassport`): four local readings, five
/// tiles and two play cards. Every number comes from this device's saved roam records; unknown
/// metrics stay unknown rather than zero.
public struct RoamPassportHome: Equatable {
    public enum Tile: String, CaseIterable, Identifiable {
        case history, stamp, badge, goals, capsule
        public var id: String { rawValue }
        public var titleKey: String { "roam.w208.passport.tile.\(rawValue)" }
        /// 探索目标 / 时光胶囊 shipped with the 2026-10-14 roam launch and carry a NEW mark.
        public var isNew: Bool { self == .goals || self == .capsule }
        /// Fixed subtitle for tiles without a count.
        public var subtitleKey: String? { self == .history || self == .stamp ? nil : "roam.w208.passport.tile.\(rawValue).sub" }
        public var symbol: String {
            switch self {
            case .history: return "point.topleft.down.to.point.bottomright.curvepath"
            case .stamp: return "photo.on.rectangle"
            case .badge: return "star"
            case .goals: return "flag"
            case .capsule: return "clock"
            }
        }
    }
    public enum Play: String, CaseIterable, Identifiable {
        /// 官方活动 is closed by product decision: the card keeps its slot and a tap does nothing.
        case event, discover
        public var id: String { rawValue }
        public var isClosed: Bool { self == .event }
        public var titleKey: String { "roam.w208.passport.play.\(rawValue)" }
        public var subtitleKey: String { "roam.w208.passport.play.\(rawValue).sub" }
    }
    public let summary: RoamPassportSummary
    public let stamps: Int
    public init(records: [RoamHistoryRecord], timeZone: TimeZone = .current) throws {
        summary = try RoamPassportSummary(records: records, timeZone: timeZone)
        stamps = records.reduce(0) { $0 + $1.photos.count }
    }
    /// History and album captions are counts (N 次旅程 / N 张邮票); the other tiles read their own pages.
    public func count(_ tile: Tile) -> Int? {
        switch tile {
        case .history: return summary.trips
        case .stamp: return stamps
        case .badge, .goals, .capsule: return nil
        }
    }
}

/// Mini-program header states above the two tabs, from this device's write-ahead journal only.
/// `finishPending` needs a check (上次漫游需要核对); `unfinished` is a recovered walk notice.
public enum RoamHomeRecoveryBanner: Equatable {
    case needsCheck, recovered
    public init?(status: RoamLocalWalkStatus) {
        switch status {
        case .finishPending: self = .needsCheck
        case .unfinished: self = .recovered
        case .none, .unavailable: return nil
        }
    }
    public var titleKey: String { self == .needsCheck ? "roam.w208.recovery.needsCheck" : "roam.w208.recovery.recovered" }
    public var accessibilityID: String { self == .needsCheck ? "roam.home.recovery.needsCheck" : "roam.home.recovery.recovered" }
}
