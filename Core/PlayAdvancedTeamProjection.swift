import Foundation

/// Current publicMultiplayer/publicRuntimeConfig projection, not the obsolete
/// mini client's `roles` alias. Other members' roles are leader-only data.
public struct PlayAdvancedTeamProjection: Equatable {
    public struct Member: Equatable, Identifiable { public let id: Int; public let name: String; public let roleID: String? }
    public struct Role: Equatable, Identifiable { public let id: String; public let label: String; public let maximum: Int }
    public let members: [Member]; public let roles: [Role]
    public let assignment: String; public let myRole: String?
    public let turnIndex: Int; public let completedUnits: Int; public let requiredTurns: Int
    public let isLeader: Bool
    public init?(state: PlayAdvancedState, actorID: Int) {
        let config = state.config["multiplayer"], value = state.multiplayer
        guard state.isMultiplayer, state.ownerType == 2, actorID > 0,
              let rawMembers = value["members"].array, !rawMembers.isEmpty, rawMembers.count <= 100,
              let index = value["turnIndex"].integer, index >= 0,
              let units = value["completedUnitIds"].array, units.count <= 10000,
              units.allSatisfy({ $0.text?.isEmpty == false }),
              let required = config["requiredTurns"].integer, required > 0,
              let assignment = config["assignment"].text, ["AUTO", "LEADER"].contains(assignment) else { return nil }
        let isLeader = value["leaderMemberId"].integer == actorID
        let assignments = isLeader ? value["roleAssignments"].object ?? [:] : [:]
        var members: [Member] = []; var ids = Set<Int>()
        for item in rawMembers {
            guard let id = item["memberId"].integer, id > 0, ids.insert(id).inserted,
                  let name = item["name"].text, !name.isEmpty, name.utf16.count <= 256 else { return nil }
            members.append(.init(id: id, name: name, roleID: assignments[String(id)]?.text))
        }
        guard ids.contains(actorID) else { return nil }
        var roles: [Role] = []; var roleIDs = Set<String>()
        if isLeader {
            for item in config["roles"].array ?? [] {
                guard let id = item["id"].text, !id.isEmpty, id.utf16.count <= 64, roleIDs.insert(id).inserted,
                      let label = item["label"].text, !label.isEmpty, label.utf16.count <= 256,
                      let maximum = item["max"].integer, maximum > 0 else { return nil }
                roles.append(.init(id: id, label: label, maximum: maximum))
            }
        }
        self.members = members; self.roles = roles; self.assignment = assignment; self.isLeader = isLeader
        self.myRole = value["myRole"].text.flatMap { $0.isEmpty || $0.utf16.count > 64 ? nil : $0 }
        self.turnIndex = index; completedUnits = Set(units.compactMap(\.text)).count; requiredTurns = required
    }
    public var canRequestUnit: Bool { myRole != nil && completedUnits < requiredTurns }
    public func canAssign(memberID: Int, roleID: String) -> Bool {
        guard isLeader, assignment == "LEADER", let member = members.first(where: { $0.id == memberID }),
              let role = roles.first(where: { $0.id == roleID }) else { return false }
        return member.roleID != roleID && members.filter { $0.roleID == roleID }.count < role.maximum
    }
    public func roleLabel(_ id: String) -> String { roles.first { $0.id == id }?.label ?? id }
}

public struct PlayAdvancedTeamReview: Identifiable {
    public enum Action: Equatable { case assign(memberID: Int, roleID: String), completeUnit }
    public let id = UUID(); public let action: Action
    public let sessionID: Int; public let nodeID: Int; public let version: Int
    public let memberName: String?; public let roleLabel: String?
    let owner: PlayExperienceSession
    let surfaceRevision: UInt64
    let surfaceID: UUID
}

public enum PlayAdvancedLeaderboardMetric: String { case elapsed = "ELAPSED_TIME", score = "SCORE", units = "COMPLETED_UNITS" }
