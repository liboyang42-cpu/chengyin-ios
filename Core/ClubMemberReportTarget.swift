import Foundation

/// P045 reportClubMember: the selected member, never a typed or inferred ID.
/// Navigation is ephemeral and grants no moderation authority.
public struct ClubMemberReportTarget: Identifiable, Hashable {
    public let id = UUID()
    public let clubID: Int
    public let memberID: Int
    public let displayName: String?
    public let context: ClubGovernanceReadContext
    public init?(member: ClubMember, directory: ClubMemberDirectory, context: ClubGovernanceReadContext) {
        guard context.operation == .members, context.scope == ClubGovernanceScope(clubID: directory.club.id),
              (1...9_007_199_254_740_991).contains(directory.club.id), directory.club.canSeeMembers, let accountID = context.identity?.accountID, accountID > 0,
              (1...9_007_199_254_740_991).contains(member.memberId), member.memberId != accountID,
              directory.members.filter({ $0.memberId == member.memberId }).count == 1,
              directory.members.contains(member) else { return nil }
        clubID = directory.club.id; memberID = member.memberId; self.context = context
        let name = member.nickname?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let name, !name.isEmpty { displayName = String(name.prefix(40)) }
        else { displayName = nil }
    }
    public var scope: ClubGovernanceScope { .init(clubID: clubID) }
    public var seed: [String: ClubGovernanceValue] { ["targetType": .string("MEMBER"), "targetId": .integer(memberID)] }
    public func isCurrent(directory: ClubMemberDirectory?, context: ClubGovernanceReadContext) -> Bool {
        guard self.context == context, let directory, directory.club.id == clubID, directory.club.canSeeMembers,
              let accountID = context.identity?.accountID, accountID > 0, accountID != memberID else { return false }
        return directory.members.filter({ $0.memberId == memberID }).count == 1
    }
}
