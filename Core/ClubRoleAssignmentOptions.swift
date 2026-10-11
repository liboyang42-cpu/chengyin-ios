import Foundation

public struct ClubRoleAssignableMember: Equatable, Identifiable {
    public let id: Int
    public let nickname: String?
}
public struct ClubRoleAssignableOption: Equatable, Identifiable {
    public var id: String { code }
    public let code: String
    public let name: String
    public var summaryKey: String { "club.rolePicker.summary." + code }
}

/// An option list is evidence for a local choice, never a role-assignment grant.
/// The existing coordinator still re-reads roles and proves membership for review.
public struct ClubRoleAssignmentOptions: Equatable {
    public let scope: ClubGovernanceScope
    public let members: [ClubRoleAssignableMember]
    public let roles: [ClubRoleAssignableOption]
    public let hasUnverifiedMembers: Bool
    public init(roles source: ClubGovernanceSnapshot, members roster: ClubGovernanceSnapshot,
                context: ClubGovernanceReadContext) throws {
        try context.scope.validate()
        guard context.operation == .roles, context.accepts(source), roster.operation == .members,
              roster.scope == context.scope, let clubID = context.scope.clubID, clubID > 0,
              (context.identity?.accountID ?? 0) > 0,
              source.permissions?.allows("ROLES", scope: context.scope) == true,
              roster.permissions?.allows("ROLES", scope: context.scope) == true else {
            throw ClubGovernanceFailure.targetChanged
        }
        guard let definitions = source.value["roles"].array, source.value["assignments"].array != nil,
              let rawMembers = roster.value.array else { throw ClubGovernanceFailure.malformed }
        let expectedKind = context.scope.activityID == nil ? "CLUB" : "EVENT"
        let allowed = context.scope.activityID == nil ? ClubGovernancePermissions.assignableClubRoles : ClubGovernancePermissions.assignableEventRoles
        var roles: [ClubRoleAssignableOption] = [], codes = Set<String>()
        for row in definitions {
            guard row.object != nil else { throw ClubGovernanceFailure.malformed }
            guard let code = row["roleCode"].string, allowed.contains(code) else { continue }
            guard row["scopeType"] == .string(expectedKind), let name = row["name"].string,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  row["permissions"].array != nil,
                  codes.insert(code).inserted else { throw ClubGovernanceFailure.malformed }
            roles.append(.init(code: code, name: name))
        }
        guard !roles.isEmpty else { throw ClubGovernanceFailure.malformed }
        var members: [ClubRoleAssignableMember] = [], ids = Set<Int>(), unverified = false
        for row in rawMembers {
            guard row.object != nil, let memberID = ClubCustomerHistoryTopicRoute.positiveID(row["memberId"]),
                  ids.insert(memberID).inserted,
                  row["clubId"] == .null || ClubCustomerHistoryTopicRoute.positiveID(row["clubId"]) == clubID else {
                throw ClubGovernanceFailure.malformed
            }
            if row["isOwner"] == .bool(true) { continue }
            // Existing memberProof requires an explicit false. Missing owner status
            // must not turn into permission through a UI default.
            guard row["isOwner"] == .bool(false) else { unverified = true; continue }
            let name = row["nickname"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            members.append(.init(id: memberID, nickname: name?.isEmpty == false ? name : nil))
        }
        scope = context.scope; self.members = members; self.roles = roles; hasUnverifiedMembers = unverified
    }
    public func contains(memberID: Int?, roleCode: String) -> Bool {
        guard let memberID else { return false }
        return members.contains(where: { $0.id == memberID }) && roles.contains(where: { $0.code == roleCode })
    }
}
