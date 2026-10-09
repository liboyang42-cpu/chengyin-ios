import Foundation

/// Presentation of one validated, current team-list response. Counts describe
/// only these loaded records, never a global total or an authorization grant.
public struct MerchantOperatorRoster: Equatable {
    public let activeMembers: [MerchantBusinessRecord]
    public let pendingInvites: [MerchantBusinessRecord]
    public let previousMembers: [MerchantBusinessRecord]
    public let previousInvites: [MerchantBusinessRecord]

    public init(document: MerchantBusinessDocument) throws {
        guard document.query == .operators else { throw MerchantBusinessFailure.malformed }
        var active: [MerchantBusinessRecord] = [], pending: [MerchantBusinessRecord] = []
        var members: [MerchantBusinessRecord] = [], invites: [MerchantBusinessRecord] = []
        for row in document.rows {
            switch (row.kind, row.fields.mbText("status")) {
            case (.operatorMember, "ACTIVE"): active.append(row)
            case (.operatorMember, "REVOKED"): members.append(row)
            case (.invite, "PENDING"): pending.append(row)
            case (.invite, "ACCEPTED"), (.invite, "EXPIRED"), (.invite, "REVOKED"): invites.append(row)
            default: throw MerchantBusinessFailure.malformed
            }
        }
        activeMembers = active; pendingInvites = pending
        previousMembers = members; previousInvites = invites
    }

    public var hasHistory: Bool { !previousMembers.isEmpty || !previousInvites.isEmpty }
}
