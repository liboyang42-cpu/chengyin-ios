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

/// A local no-change return ticket, never an operator mutation or permission grant.
public struct MerchantOperatorRoleNoChange {
    public let editorID: UUID
    private let record: MerchantBusinessRecord
    private let role: String
    private let document: MerchantBusinessDocument
    public init?(editorID: UUID, record: MerchantBusinessRecord, selectedRole: String, document: MerchantBusinessDocument) {
        guard document.query == .operators, record.kind == .operatorMember,
              document.rows.filter({ $0.kind == .operatorMember && $0.id == record.id }).count == 1,
              document.rows.contains(record), record.fields.mbText("status") == "ACTIVE",
              let version = record.fields["version"]?.integer, version >= 0,
              !selectedRole.isEmpty, record.fields.mbText("roleCode") == selectedRole else { return nil }
        self.editorID = editorID; self.record = record; role = selectedRole; self.document = document
    }
    public func matches(editorID: UUID, record: MerchantBusinessRecord, selectedRole: String, document: MerchantBusinessDocument) -> Bool {
        self.editorID == editorID && self.record == record && role == selectedRole && self.document == document
    }
    public func matches(editorID: UUID, document: MerchantBusinessDocument) -> Bool {
        self.editorID == editorID && self.document == document
    }
}
