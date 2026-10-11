import Foundation

public struct ClubSeriesLeadMember: Equatable, Identifiable {
    public let id: Int
    public let nickname: String?
}

/// Named, explicit members for new-series lead selection, not a role assignment or write grant.
public struct ClubSeriesLeadOptions: Equatable {
    public let scope: ClubGovernanceScope
    public let members: [ClubSeriesLeadMember]
    public init(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) throws {
        try context.scope.validate()
        guard context.operation == .members, context.accepts(snapshot),
              let clubID = context.scope.clubID, clubID > 0, (context.scope.topicID ?? 0) > 0,
              context.scope.activityID == nil, context.scope.seriesID == nil,
              (context.identity?.accountID ?? 0) > 0 else { throw ClubGovernanceFailure.targetChanged }
        guard snapshot.permissions?.allows("club:activity:manage", scope: context.scope) == true else { throw ClubGovernanceFailure.forbidden }
        guard let rows = snapshot.value.array else { throw ClubGovernanceFailure.malformed }
        var projected: [ClubSeriesLeadMember] = [], seen = Set<Int>()
        for row in rows {
            guard row.object != nil, let memberID = ClubCustomerHistoryTopicRoute.positiveID(row["memberId"]),
                  row["clubId"] == .null || ClubCustomerHistoryTopicRoute.positiveID(row["clubId"]) == clubID else {
                throw ClubGovernanceFailure.malformed
            }
            // Mini keeps the first occurrence of each memberId. Owners are also eligible here;
            // unlike role assignment, existing series memberProof does not require isOwner=false.
            guard seen.insert(memberID).inserted else { continue }
            let name = row["nickname"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            projected.append(.init(id: memberID, nickname: name?.isEmpty == false ? name : nil))
        }
        scope = context.scope; members = projected
    }
    public func contains(memberID: Int?) -> Bool {
        guard let memberID else { return false }
        return members.contains { $0.id == memberID }
    }
}
