import Foundation

/// Mini-program subpackageRoam/nearby list badges (`_syncTeams` BADGE table), keyed only on the read card mode.
public enum NearbyTeamBadge: String, CaseIterable {
    case buy, apply, pending, joined, rejected, leader
    public init(mode: String) { self = Self(rawValue: mode) ?? .apply }
    public var key: String { "nearby.w208.badge.\(rawValue)" }
}

/// Read-failure presentation for the nearby map/list (xcx `nearbyReadAccess` login/denied plus load failure).
public enum NearbyLoadIssue: String, Equatable {
    case signIn, denied, failed
    public init?(messageKey: String?) {
        switch messageKey {
        case "nearby.signIn": self = .signIn
        case "nearby.w208.denied": self = .denied
        case "nearby.loadFailed", "nearby.unconfigured": self = .failed
        default: return nil
        }
    }
    public var titleKey: String { "nearby.w208.issue.\(rawValue)" }
    public var actionKey: String { self == .signIn ? "nearby.w208.issue.signInAction" : "nearby.w208.issue.retry" }
}

/// Pure copy helpers mirroring `subpackageRoam/utils/map-team.js` and `my-teams/index.js`.
/// Values come only from already-read server rows; nothing here reads location or invents counts.
public enum NearbyTeamPresentation {
    /// my-teams loads its 附近招募 rows at a fixed 3 km, independent of the map's 1 km default.
    public static let recruitingRadius = 3000

    /// `km()`: below 1000 m whole metres, otherwise one decimal kilometre without a trailing `.0`.
    public static func distanceText(_ meters: Double) -> String {
        let value = meters.isFinite ? max(0, meters) : 0
        guard value >= 1000 else { return "\(Int(value.rounded())) m" }
        let km = (value / 100).rounded() / 10
        return km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km)
    }
    public static func rangeText(_ radius: Int) -> String { distanceText(Double(radius)) }
    /// Seats still open; zero means 已满员. A missing capacity is never treated as open seats.
    public static func remainingSeats(_ team: NearbyTeam) -> Int { max(0, team.maxMembers - team.joinedCount) }
    public static func heading(_ team: NearbyTeam) -> String { team.activityName.isEmpty ? team.title : team.activityName }
    /// `addressName + 集合|附近`; empty when the server supplied no place.
    public static func placeIsGather(_ team: NearbyTeam) -> Bool { team.coordSource == "GATHER" }
    /// my-teams avatar stack: real faces first, padded with default faces up to the member count, 1...3.
    public static func faceCount(real: Int, members: Int?) -> Int { max(1, min(3, max(real, members ?? 1))) }
    /// my-teams `dateText`: `yyyy-MM-dd HH:mm…` → `MM/dd HH:mm`; anything shorter is not shown.
    public static func startText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "T", with: " "))
        guard text.count >= 16 else { return nil }
        let slice = String(text[5..<16])
        guard slice.range(of: #"^\d{2}-\d{2} \d{2}:\d{2}$"#, options: .regularExpression) != nil else { return nil }
        return slice.replacingOccurrences(of: "-", with: "/")
    }
    /// 附近招募 only lists teams the viewer has not applied to or joined (`viewerStatus === 'NONE'`).
    public static func recruiting(_ teams: [NearbyTeam]) -> [NearbyTeam] { teams.filter { $0.viewerStatus == .none } }
}
