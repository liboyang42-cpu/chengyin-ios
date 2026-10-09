import Foundation
import Observation

/// Public team ranking from the existing PLAYER game-session projection.
/// Score is the server's distinct normally completed node count, not a reward.
public struct PlayPlayerLeaderboardEntry: Equatable, Identifiable {
    public let id: Int
    public let rank: Int
    public let displayName: String?
    public let score: Int
}

public enum PlayPlayerLeaderboardState: Equatable {
    case hidden, unconfirmed, empty
    case entries([PlayPlayerLeaderboardEntry])

    /// Only an explicit server visibility grant allows any leaderboard UI.
    /// Do not recover hidden entries, filter invalid rows or calculate ranks.
    public static func read(_ value: PlayWireValue) -> Self {
        guard value.object != nil, value["visible"].bool == true else { return .hidden }
        guard let rows = value["entries"].array else { return .unconfirmed }
        var seenTeams = Set<Int>()
        var previousRank = 0
        var entries: [PlayPlayerLeaderboardEntry] = []
        for row in rows {
            guard row.object != nil, let id = safeInteger(row["teamId"]), id > 0,
                  seenTeams.insert(id).inserted,
                  let rank = safeInteger(row["rank"]), rank > previousRank,
                  let score = safeInteger(row["score"]), score >= 0,
                  validOptionalName(row["displayName"]) else { return .unconfirmed }
            previousRank = rank
            entries.append(.init(id: id, rank: rank, displayName: name(row["displayName"]), score: score))
        }
        return entries.isEmpty ? .empty : .entries(entries)
    }
    private static func safeInteger(_ value: PlayWireValue) -> Int? {
        guard let number = value.integer, number >= 0, number <= 9_007_199_254_740_991 else { return nil }
        return number
    }
    private static func validOptionalName(_ value: PlayWireValue) -> Bool {
        if value == .null { return true }
        guard let name = value.text, name.count <= 80 else { return false }
        return !name.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    private static func name(_ value: PlayWireValue) -> String? {
        guard let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// A read-only screen lease. The existing submission reader owns the network
/// request. This keeps no second projection or command state.
@available(macOS 14.0, *)
@MainActor @Observable public final class PlayPlayerLeaderboardReadback {
    private let model: PlayPlayerGameCoordinator
    private let owner: PlayExperienceSession?
    private var sessionID: Int?
    private var teamID: Int?
    private var minimumRevision: Int?
    private var retired = false

    public init(model: PlayPlayerGameCoordinator) {
        self.model = model; owner = model.currentSession()
    }
    private var currentAuthority: Bool {
        !retired && owner != nil && owner == model.currentSession()
            && model.service.enabled.contains(.reads) && model.service.hasCurrentReadLifetime
            && model.hasCurrentProjection && model.phase == "ready" && model.pending == nil
    }
    /// Accept only after the existing reader completes. The first scope stays
    /// fixed; later reads can advance the revision floor, never lower it.
    public func acceptFreshRead() {
        guard currentAuthority, !Task.isCancelled, let projection = model.projection,
              projection.activityID == model.activityID else { return }
        if let sessionID, let teamID {
            guard sessionID == projection.sessionID, teamID == projection.teamID else {
                retired = true; return
            }
            minimumRevision = max(minimumRevision ?? 0, projection.revision)
        } else {
            sessionID = projection.sessionID; teamID = projection.teamID
            minimumRevision = projection.revision
        }
    }
    public var state: PlayPlayerLeaderboardState {
        guard currentAuthority, let projection = model.projection,
              projection.activityID == model.activityID,
              sessionID == projection.sessionID, teamID == projection.teamID,
              let minimumRevision, projection.revision >= minimumRevision else { return .hidden }
        return PlayPlayerLeaderboardState.read(projection.playerLeaderboard)
    }
    public func dismiss() { retired = true }
}
