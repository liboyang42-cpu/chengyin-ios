import Foundation

/// Mini openAcceptedProject: only the merchant side of a current accepted invitation.
public struct MerchantAcceptedProjectRoute: Equatable {
    public let invitationID: Int
    public let topicID: Int
    public let direction: CooperationDirection
    public init?(row: CoopFlowJSON, direction: CooperationDirection) {
        func positive(_ value: CoopFlowJSON) -> Int? {
            switch value {
            case .number:
                guard let id = value.integer, id > 0, id <= 9_007_199_254_740_991 else { return nil }; return id
            case .string(let text):
                guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
                      let id = Int(text), id > 0 else { return nil }; return id
            default: return nil
            }
        }
        guard row["status"].integer == 1,
              (row["inviteType"].integer == 0 && direction == .received) ||
              (row["inviteType"].integer == 1 && direction == .sent),
              let invitation = positive(row["id"]), let topic = positive(row["topicId"]) else { return nil }
        switch row["legacyReadonly"] { case .null, .bool(false): break; default: return nil }
        switch row["identityError"] { case .null, .bool(false), .string(""): break; default: return nil }
        if row["inviteId"] != .null, positive(row["inviteId"]) != invitation { return nil }
        invitationID = invitation; topicID = topic; self.direction = direction
    }
    public var sourceKey: String { direction == .received ? "received" : "sent" }
    public func matchesUniqueRow(_ rows: [CoopFlowJSON]) -> Bool {
        let matches = rows.filter { $0["id"].integer == invitationID }
        return matches.count == 1 && MerchantAcceptedProjectRoute(row: matches[0], direction: direction) == self
    }
}
