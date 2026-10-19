import Foundation

public struct CoopFlowTargetCandidate: Equatable, Identifiable {
    public let kind: CoopFlowTargetKind
    public let recipient: CoopFlowIdentity
    public let name: String
    /// Source `pages/coop/invite` row meta: clubs show member count and city, merchants their activity types or address.
    public let memberCount: Int?
    public let city: String?
    public let merchantMeta: String?
    public var id: String { "\(kind.rawValue):\(recipient.id)" }
    public init?(kind: CoopFlowTargetKind, row: CoopFlowJSON) {
        // Current merchant directory exposes BOTH row id and memberId. Invitations address
        // the owner-member; club invitations address club.id. No fallback across domains.
        guard let id = row[kind == .merchant ? "memberId" : "id"].integer,
              let recipient = try? CoopFlowIdentity(kind == .merchant ? .member : .club, id),
              let name = row["name"].text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        self.kind = kind; self.recipient = recipient; self.name = name
        func text(_ key: String) -> String? { row[key].text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 } }
        memberCount = kind == .club ? row["memberCount"].integer.flatMap { $0 >= 0 ? $0 : nil } : nil
        city = kind == .club ? text("city") : nil
        merchantMeta = kind == .merchant ? text("suitActivityTypes") ?? text("address") : nil
    }
}
public struct CoopFlowOwnedTopic: Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let startDate: String?
    public let address: String?
    public let inviteWindowOpen: Bool?
    public init?(row: CoopFlowJSON) {
        guard let id = row["id"].integer, id > 0, let name = row["name"].text, !name.isEmpty else { return nil }
        self.id = id; self.name = name; startDate = row["startDate"].text; address = row["addressName"].text
        inviteWindowOpen = row["inviteWindowOpen"].flag
    }
}
/// This projection is a member ID only. Club identities must first be resolved by an
/// authoritative owner-member contract; neither club.id nor a missing fromType is one.
public struct CoopPeerMember: Equatable {
    public let memberID: Int
    public init?(direction: CooperationDirection, fromType: String?, fromID: Int?, toType: String?, toID: Int?) {
        let raw: Int?
        switch direction {
        case .sent: guard toType == "merchant" else { return nil }; raw = toID
        case .received: guard ["merchant", "talent"].contains(fromType ?? "") else { return nil }; raw = fromID
        }
        guard let raw, raw > 0 else { return nil }; memberID = raw
    }
}
